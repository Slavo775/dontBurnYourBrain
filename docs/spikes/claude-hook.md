# Spike: a Claude Code hook reports a session

Card #5, phase 0. What a hook that Claude Code runs can tell the app about a session, its terminal tab and its profile, and whether the hook can be put into a profile's settings and taken out again without a trace.

Tested with Claude Code 2.1.326 on macOS, in a scratch project in Terminal and iTerm2, and by hand in VS Code and Cursor. The Tester repeated the scratch-project result in Terminal and iTerm2 and got the same order and timings, within one to three seconds. The spike's code and the steps to repeat it are in [Spikes/claude-hook/README.md](../../Spikes/claude-hook/README.md).

## The answers

1. **Which events the app needs.** `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure` and `SessionEnd`. `UserPromptSubmit` means "working". `PermissionRequest`, and `Notification` with `permission_prompt`, mean "waiting for you". `Stop` means "finished" unless its `background_tasks` still lists a subagent, a workflow or a teammate. Every event carries the session id, the working folder and the transcript path. After a denied permission or an Esc no `Stop` comes, so the app needs a fallback there.
2. **Which terminal and which tab.** Yes for Terminal and iTerm2, down to the tab, and both handles match what the terminal's own AppleScript reports. VS Code and Cursor can be told apart, but they give no tab id, so focus stays at window level. A terminal the hook doesn't know gives a session without a focus button.
3. **Which profile.** Yes. `CLAUDE_CONFIG_DIR` when it is set, otherwise the part of `transcript_path` before `/projects/`. This holds when several profiles share one settings file.
4. **Install and uninstall without a trace.** Yes, for a settings file that comes back byte for byte from a two-space JSON round trip. The spike's installer refuses any other file. On a real profile it was installed for 50 seconds, and the file came back byte-identical.
5. **Main thread stopped, subagents still working.** Yes. Each `Stop` lists the work still running in `background_tasks`. The owner decided that only subagents, workflows and teammates keep a session "working".

## Events and what each one means for the app

Every event carries `session_id`, `transcript_path`, `cwd`, `hook_event_name` and `scratchpad_dir`. The table lists what comes on top.

| Event | Extra fields | State for the app |
|---|---|---|
| `SessionStart` | `source` (`startup`, `resume`, `clear`, `compact`, `fork`), `model` | Register the session |
| `UserPromptSubmit` | `prompt`, `prompt_id`, `permission_mode` | **Working.** It also fires when finished background work wakes the main thread. Then the prompt starts with `<task-notification>`, and nobody typed it |
| `PermissionRequest` | `tool_name`, `tool_input`, `permission_suggestions`, `permission_mode`, `effort`, `prompt_id` | **Waiting for you**, at once, about two seconds after the prompt |
| `Notification` | `message`, `notification_type`, `prompt_id` | `permission_prompt`: **waiting for you**, about six seconds after the request, and only while the user isn't typing. The app needs it because sandbox network prompts skip `PermissionRequest`. `idle_prompt`: 60 seconds after a `Stop`, no new state. `auth_success`: after a sign-in, ignore |
| `Stop` | `stop_hook_active`, `last_assistant_message`, `background_tasks`, `session_crons`, `permission_mode`, `effort`, `prompt_id` | **Finished**, unless `background_tasks` holds a subagent, a workflow or a teammate. Then still **working** |
| `StopFailure` | `error`, `last_assistant_message`, `prompt_id` | **Finished, with an error.** The turn ended on an API error. It comes instead of `Stop`. Seen in Cursor |
| `SessionEnd` | `reason`, `prompt_id` | **Gone.** `/exit` and two Ctrl-D give `prompt_input_exit`. Closing the tab sends SIGHUP to `claude` and gives `other` |
| `SubagentStart` | `agent_id`, `agent_type`, `prompt_id` | Optional: a live subagent count |
| `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `session_crons`, `stop_hook_active` | Optional |
| `PreToolUse`, `PostToolUse` on `Agent` | `tool_name`, `tool_input`, `tool_use_id`. Post adds `tool_response` and `duration_ms` | Not needed. `tool_response.status` is `async_launched` for a background subagent and `completed` for a foreground one |

### Event orders for the basic cases

Seconds count from the prompt.

- **A prompt:** `UserPromptSubmit`, then `Stop` with `background_tasks: []` after one to two seconds.
- **A permission, approved:** `UserPromptSubmit` → `PermissionRequest` +2 s → `Notification permission_prompt` +8 s → the user answers "Yes" → `Stop`.
- **Idle:** `Notification idle_prompt` exactly 60 seconds after the last `Stop`, three times out of three.
- **A permission, denied:** `UserPromptSubmit` → `PermissionRequest` → `permission_prompt` → "No" → **no `Stop`**. An `idle_prompt` came about three minutes after the prompt. The moment of the denial wasn't logged, so it is unclear what that counts from.
- **Esc while Claude works:** `UserPromptSubmit`, Esc two seconds later → **no event at all**, and no `idle_prompt` within two minutes.
- **The end:** `/exit` or two Ctrl-D give `SessionEnd prompt_input_exit`. SIGHUP gives `SessionEnd other`.

## Subagents: when the main thread stops before its subagents

`Stop.background_tasks` lists the work that is still running. Each entry has an `id`, a `type`, a `status` and an `agent_type`. The types are `subagent`, `shell`, `monitor`, `workflow`, `teammate`, `cloud session` and `MCP task`. Only `subagent` and `shell` were seen in the spike. The others come from Claude Code's documentation.

**The owner's decision for phase 3:** only background `subagent`, `workflow` and `teammate` entries keep a session "working". A background `shell`, such as a dev server, does not. So the session is working from `UserPromptSubmit` until a `Stop` or `StopFailure` whose `background_tasks` holds none of those three types.

What Claude Code does:

- Subagents run in the background by default. This is fork mode, on by default since Claude Code 2.1.302. A subagent the main thread waits for needs `CLAUDE_CODE_FORK_SUBAGENT=0` and `run_in_background: false`.
- When a background subagent finishes, the main thread wakes up without a typed prompt: `SubagentStop`, then `UserPromptSubmit` with a `<task-notification>` prompt, then a `Stop` with one entry fewer.
- `idle_prompt` stays quiet while a background subagent runs. It came 60 seconds after the final `Stop`.
- About a second after many `Stop`s comes a `SubagentStop` with an empty `agent_type` and no `SubagentStart` before it. That is an agent Claude Code runs for itself, for prompt suggestions. The app ignores it.
- `SubagentStop.background_tasks` still lists the subagent that is stopping. So `SubagentStop` can't tell when the last one is done. `Stop` can.
- Two subagents that finish close together can flicker. In one run a `Stop` with `[]` came, and two seconds later one more `UserPromptSubmit` and `Stop`. A debounce of about two seconds covers it.

Below, A and B are the two subagents, "internal" is Claude Code's own agent, and `bg` is `background_tasks`. Seconds count from the typed prompt.

**Case a: two background subagents.** A waits 30 seconds, B waits 45.

```
+0   UserPromptSubmit typed                                     working
+1   PreToolUse Agent
+2   SubagentStart A · PostToolUse async_launched · PreToolUse Agent · SubagentStart B · PostToolUse async_launched
+3   Stop bg=[subagent running, subagent running]               main thread stopped, still working
+4   SubagentStop internal
+34  SubagentStop A
+34  UserPromptSubmit tag:task-notification                     main thread resumes
+35  Stop bg=[subagent running]                                 still working
+36  SubagentStop internal
+49  SubagentStop B
+49  UserPromptSubmit tag:task-notification
+50  Stop bg=[]                                                 finished
+51  SubagentStop internal
```

The Tester's run gave the same order. A and B were 15 seconds apart, as here.

So the session stays "working" through every `Stop` that still lists a subagent, and through each `<task-notification>` turn in between. It is "finished" at the first `Stop` whose list holds no subagent, workflow or teammate, here at +50.

**The background-shell variant.** The two subagents started their waits as background shells and returned after six seconds.

- The first `Stop` listed two `shell` entries with status `running`.
- When each shell ended, about 27 and 38 seconds after that `Stop`, its subagent was resumed. A second `SubagentStart` came for the same `agent_id`, then `SubagentStop`, `UserPromptSubmit` with `<task-notification>`, and `Stop`.
- The final `Stop`, 40 seconds after the first, had `bg=[]`.

Under the owner's rule, the first `Stop` already means "finished", because it lists only shells. Each time a shell ends, the session is "working" again for a few seconds, until the next `Stop`.

**Case b: a foreground subagent.** With `CLAUDE_CODE_FORK_SUBAGENT=0` and `run_in_background: false`, the subagent waits 20 seconds.

```
+0   UserPromptSubmit                                           working
+1   PreToolUse Agent (run_in_background false) · SubagentStart
     no event for 23 seconds, still inside the main thread's turn
+24  SubagentStop · PostToolUse completed
+25  Stop bg=[]                                                 finished
+26  SubagentStop internal
```

The Tester's run gave the same, with 25 seconds without an event.

**Case c: `/exit` while a background subagent works.** The subagent waits 60 seconds.

```
+0   UserPromptSubmit                                           working
+1   PreToolUse Agent · PostToolUse async_launched · SubagentStart
+2   Stop bg=[subagent running]                                 still working
+4   SubagentStop internal
+13  /exit opens a dialog: "Exit and stop tasks", "Move to background and exit", "Stay". No event
+42  after "Exit and stop tasks": SessionEnd prompt_input_exit  gone
```

No `SubagentStop` came for the running subagent, and its processes were gone. "Move to background and exit" keeps a session alive with no terminal. It was not tested.

## Which terminal and which tab

The hook's direct parent is always the `claude` process, for subagent events too. The hook itself has no tty, so the tab's tty is the tty of its parent. Claude Code exports the parent's pid as `CLAUDE_PID`. It matched the hook's parent pid in every event checked, 171 of 171.

| Terminal | `TERM_PROGRAM` | Bundle id (`__CFBundleIdentifier`) | Tab id | Ancestors after `claude` | Handle for focus |
|---|---|---|---|---|---|
| Terminal | `Apple_Terminal` | `com.apple.Terminal` | `TERM_SESSION_ID`, a bare UUID | `-bash` → `login` → `Terminal` | **The tty.** It equals AppleScript's `tty of tab 1 of window id <id>`. AppleScript doesn't show `TERM_SESSION_ID` |
| iTerm2 | `iTerm.app` | `com.googlecode.iterm2` | `ITERM_SESSION_ID`, shaped `w<n>t<n>p<n>:<UUID>`. `TERM_SESSION_ID` holds the same value. Also `LC_TERMINAL=iTerm2` | `-bash` → `login` → `iTermServer-<version>` → `iTerm2` | **The UUID after the colon.** It equals the session's AppleScript `unique ID`, and the tty equals its `tty` |
| VS Code | `vscode` | `com.microsoft.VSCode` | None | `bash` → `Code Helper` → `Code` | None. Not scriptable, so the window is found by its folder |
| Cursor | `vscode` | `com.todesktop.230313mzl4w4u92` | None | `bash` → `Cursor Helper: terminal pty-host` → `Cursor` | None. Not scriptable, so the window is found by its folder |
| Unknown | none | none | none | no terminal app | None. The session is listed without a focus button |

- Terminal and iTerm2 were each checked in at least two tabs or windows, and the handles matched every time. Two Terminal tabs had different ttys and different `TERM_SESSION_ID`s.
- VS Code and Cursor set the same `TERM_PROGRAM` and the same `VSCODE_*` variables, and neither sets a `CURSOR_*` variable. The bundle id or the ancestor names tell them apart. Both set `CLAUDE_CODE_SSE_PORT` when Claude Code's IDE extension is connected.
- **A tty is reused at once.** In the spike, a closed Terminal tab's tty went to a new iTerm2 window within a minute. So the app knows a tab by its tty together with the `claude` pid and the session id.
- The spike hook found the tty by listing every process with `ps -A`. That took 0.12 of its 0.16 seconds per call. Phase 3 can read the parent's tty with one `sysctl` call instead. *24 Nov 2026:* card #48 does. The hook tool reads the tty of the process `CLAUDE_PID` names with one `sysctl` call.

## Which profile

**The rule for phase 3:**

1. `CLAUDE_CONFIG_DIR`, when it is set.
2. Otherwise the part of `transcript_path` before `/projects/`.
3. Otherwise the default profile, `~/.claude`.

How it was seen:

- When a profile is chosen with `CLAUDE_CONFIG_DIR`, the hook sees that variable unchanged. This held in Terminal, iTerm2, VS Code and the real-profile test, and on 50 of 50 events in the Tester's run.
- `transcript_path` is `<profile folder>/projects/<folder name>/<session id>.jsonl`. The folder name is the absolute `cwd` with every character that is not a letter or a digit turned into `-`, so `/`, `.` and `_` all become `-`. The rule above only needs the part before `/projects/`, so the folder name doesn't matter for it.
- Without `CLAUDE_CONFIG_DIR`, in the owner's Cursor run, `transcript_path` sat under `~/.claude/projects/`, the default profile.
- **A shared settings file doesn't change this.** The hook comes from the shared file, but the event names the profile Claude Code was started with.
- Putting the profile into the hook command at install time, as in `--profile <id>`, would be simpler, but it can't work on a shared settings file. So the app reads the profile from the event.
- On the test Mac, `claude` in a login shell is a wrapper that asks for a profile. The runs went around it with `command claude` and `CLAUDE_CONFIG_DIR`.

## Install and uninstall

### What the spike did

`profile-step.sh` has three steps for a profile's `settings.json`:

- **precheck** stops when `jq` is missing, or the file is a symlink, missing, not a JSON object, or not byte-identical after a two-space `jq` round trip. It also stops when `hooks` is not an object of lists of groups.
- **install** runs the precheck again and copies the file to a backup. It records whether `hooks` existed and which event lists it had. It adds one group per event to eight events: `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop` and `SessionEnd`. It writes the file in place, which keeps its inode, its mode and whether it ends with a newline.
- **uninstall** removes only groups whose command is the spike's, then any event list or `hooks` key the install created. It compares the file with the backup. When they differ, it names the top-level keys that differ and exits with an error. It never writes the backup back, because the difference can be someone else's change.

Its self-test runs 30 cases on made-up files, and all pass. The cases, together with the review's checks by hand:

| Case | Result |
|---|---|
| Two-space JSON with another tool's hook | Byte-identical after uninstall |
| No newline at the end | Byte-identical |
| No `hooks` key, or `"hooks": {}` | Byte-identical |
| Hand-formatted, with four spaces | Precheck stops, because a round trip would change it |
| A symlink, a missing file, `"hooks": []` or `"hooks": null` | Precheck stops |
| Changed by someone else while installed | The spike's groups are removed, the other change is kept and named, and it exits with an error |
| Uninstall with a work folder that holds no install | Stops, nothing written |
| A second install | Stops, nothing written, the first backup kept |
| A work path with a space, `$` or a backtick, or without the hook in it | Stops, nothing written |

### On a real profile

With the owner's yes, on profile 1. **Every profile on the test Mac links its `settings.json` by symlink to one shared settings file.** The first precheck stopped on the symlink. The owner then approved a test on the shared file itself, so this one test covered every profile.

- The precheck of the shared file passed.
- Installed for 50 seconds.
- A proof session in iTerm2 under profile 1 logged `SessionStart startup`, `UserPromptSubmit`, `Stop` and `SessionEnd prompt_input_exit`. `CLAUDE_CONFIG_DIR` and `transcript_path` both named profile 1, and the tty and the iTerm2 UUID matched AppleScript.
- After uninstall, none of the spike's groups was left, and the file was byte-identical to the backup. It was still identical at clean-up.
- The log held four events, all from the proof session. No other session fired the hook during those 50 seconds, but they may simply have been idle. Whether running sessions pick up a changed settings file was not tested. In the scratch project, a permission rule added to the settings mid-session did take effect without a restart. *24 Nov 2026:* card #49 tried it in a scratch project on Claude Code 2.1.331. A session that was already running picked up a hook added to the project's `.claude/settings.json` at its next prompt, with no restart and no notice. A profile's own `settings.json` was not tried. Card #55 checks it, with the owner's own install from the Release build.

### Rules for phase 3's installer

From the spike and from the review of its two rounds:

1. Resolve a symlinked `settings.json`. Write the target in place and never replace the link. Tell the user that every profile sharing the file is affected.
2. Check before the install that the file survives a two-space round trip byte for byte, and that `hooks` is absent or an object of lists.
3. Write two-space JSON, the way Claude Code writes its settings.
4. Write nothing unless the new content is a JSON object. A failed step must never leave an empty file.
5. Refuse a second install over an existing one.
6. Always write an absolute path to the hook in the command.
7. Remember what the install created: which containers, the target file's path and its inode. Uninstall acts only on that file, and only while it still holds this install's own entries. The spike's uninstall, pointed at a file it never installed into, still rewrites that file. That is a low-severity finding the spike left unfixed.
8. Remove only the app's own groups and the containers the install created.
9. Compare after uninstall. If someone else changed the file meanwhile, keep the change and report it. Never restore a backup over it.

*24 Nov 2026:* card #49 built the installer on these rules, in `HookSettings`, `HookInstaller` and `JSONText` in `DontBurnCore`, with Settings, Sessions on top ([design.md](../spec/design.md#sessions)). Where it differs from the spike:

- **No `jq`.** `JSONText` keeps the order of keys and each number as written, and writes two-space JSON the way `JSON.stringify(value, null, 2)` does. Its parser is strict: it refuses a repeated key, compared by its bytes, nesting deeper than 256, and text that is not valid UTF-8. Every file it does not write back byte for byte is refused, with the lines to add by hand.
- **Not in place.** The new text goes into a new file beside the target, made for this user alone and flushed to the disk, then given the target's mode. It is renamed over the target only after a fresh read shows the target unchanged. A link stays a link, and its target is written. The target gets a new inode.
- **Hard links are refused**, because the rename would split them. The lines to add by hand are shown.
- **Nine events**, the eight above and `StopFailure`, the list `HookEvent.handledNames`, which the app's own session rules use too. Each group runs the command with `"timeout": 5`, which only bounds a hang.
- **The record and the backup** go to `HookInstalls/` in the app's own folder, the one named after the bundle identifier, never into a profile. Both are mode 0600 and never overwritten. The backup is removed after an uninstall that gives the file back byte for byte, and kept otherwise.
- **Rule 7:** when another file stands at the path since the install, the uninstall still takes out the app's own groups, and says the file was replaced. It looks only in the lists of `HookEvent.handledNames`. A file that holds none of its groups is not written.
- **A hook found without a record**, such as one added by hand, counts as installed and is removed by hand.

The product rules behind these, that hooks are reversible and are installed only with consent, are in [rules/safety-and-privacy.md](../../rules/safety-and-privacy.md).

## Release and Dev

How the hook tool chooses between the two builds is set in [docs/process/releases.md](../process/releases.md), and the rule for agents is in [rules/releases.md](../../rules/releases.md). The spike adds these points for phase 3:

- Real profiles get `dontburn-hook` with no target, which reaches the Release app. Scratch projects get `dontburn-hook --target dev` or `DONTBURN_TARGET=dev`. *24 Nov 2026:* card #48 takes a target only from no arguments or exactly `--target dev` or `--target release`. Any other form, such as `--target=dev`, sends nothing. *24 Nov 2026:* card #49 puts the tool inside the app, at `Contents/Helpers/dontburn-hook`, and writes that absolute path in single quotes. The Release build writes no target. The Dev build writes `--target dev`, and installs only into a stand-in folder, never into a real profile ([dev-setup.md](../spec/dev-setup.md#launch-arguments)).
- The tool derives its channel from the bundle identifier, such as a socket under `~/Library/Application Support/<bundle id>/`. *24 Nov 2026:* card #48 made it `Hook.socket`, a Unix datagram socket in that folder, and the tool sends each event as one datagram ([tech-stack.md](../spec/tech-stack.md#architecture)).
- When the channel is missing or refuses the connection, the tool exits 0 at once. The app may not be running, and a session must never wait for it. *24 Nov 2026:* card #48 sends without waiting. With no app, a socket left behind or a full queue, the event is lost.
- It prints nothing. Anything a `SessionStart` or `UserPromptSubmit` hook prints goes into Claude's context.
- It finishes well under 100 ms. All `SessionEnd` hooks share a budget of 1.5 seconds. *24 Nov 2026:* card #48 measured the Debug build, 50 calls at a time with an event of 300 to 371 bytes: median 11 to 14 ms, p90 about 16 ms, at most 30 ms, whether the app ran or not. An empty command took 5 to 8 ms in the same harness. A 3 MB event took 26 ms.
- It sends only the fields listed in the next section. *24 Nov 2026:* card #48 sends fewer, the fields of `HookEvent` from card #47. From the event: `hook_event_name`, `session_id`, `cwd`, `transcript_path`, `source`, `notification_type`, `agent_type`, and the `type` of each entry in `background_tasks`. From the environment: `CLAUDE_CONFIG_DIR`, `__CFBundleIdentifier` and `ITERM_SESSION_ID`. From the process: the `claude` pid from `CLAUDE_PID`, and its tty.

## The event format and the fields the app uses

Claude Code passes each event as one JSON object on the hook's standard input. The spike logged one line per event. A made-up example, with paths written with `~`:

```json
{"ts":1790000000000,"at":"09:00:00","event":"SessionStart",
 "keys":["cwd","hook_event_name","model","scratchpad_dir","session_id","source","transcript_path"],
 "session_id":"00000000-0000-4000-8000-000000000001","cwd":"~/code/acme-web",
 "transcript_path":"~/.claude-acme/projects/-Users-<name>-code-acme-web/00000000-0000-4000-8000-000000000001.jsonl",
 "source":"startup","model":"claude-haiku-5-5","tty":"ttysNNN",
 "env":{"TERM_PROGRAM":"Apple_Terminal","TERM_PROGRAM_VERSION":"488.9","TERM_SESSION_ID":"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
        "__CFBundleIdentifier":"com.apple.Terminal","CLAUDE_CONFIG_DIR":"~/.claude-acme","CLAUDE_PID":"30002",
        "CLAUDE_CODE_SESSION_ID":"00000000-0000-4000-8000-000000000001","CLAUDE_CODE_ENTRYPOINT":"cli"},
 "ancestors":[{"pid":30003,"tty":"??","comm":"bash"},{"pid":30002,"tty":"ttysNNN","comm":"claude"},
              {"pid":30001,"tty":"ttysNNN","comm":"-bash"},{"pid":30000,"tty":"ttysNNN","comm":"login"},
              {"pid":600,"tty":"??","comm":"Terminal"}]}
```

**The fields the app uses:**

- **From the event:** `hook_event_name`, `session_id`, `cwd`, `transcript_path`, `source`, `reason`, `notification_type`, `tool_name`, `agent_id`, `agent_type`, and the `type` and `status` of each entry in `background_tasks`. Optionally a flag for a typed prompt versus a `<task-notification>`, worked out in the hook so the prompt itself is never sent.
- **From the environment:** `TERM_PROGRAM`, `TERM_SESSION_ID`, `ITERM_SESSION_ID`, `__CFBundleIdentifier` and `CLAUDE_CONFIG_DIR`.
- **From the process:** the parent's pid and its tty.

**What the hook must never send:**

- Content: `prompt`, `last_assistant_message`, `tool_input`, `permission_suggestions`, `message` and `error`.
- The environment as a whole. It carries `CLAUDE_CODE_MESSAGING_TOKEN`, and in Cursor also `VSCODE_GIT_IPC_AUTH_TOKEN`.

Claude Code also exports `CLAUDE_CODE_SESSION_ID`, equal to `session_id`, and `CLAUDE_PROJECT_DIR`, `CLAUDE_CODE_ENTRYPOINT=cli`, `CLAUDECODE=1`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_SESSION_ATTENDED` and `CLAUDE_ENV_FILE`. The app doesn't need them.

## Gaps and what failed

**Gaps the app has to live with:**

- **A turn can end without an event.** After a denied permission or an Esc, no `Stop` comes. The app would keep showing "waiting" or "working" until the next event. Options for phase 3: a `PostToolUse` hook on every tool, to leave "waiting" after an answer; the transcript file's modification time, read for its date only; or a timeout. *24 Nov 2026:* card #47 took none of these. The `idle_prompt` notification ends the turn, and after an Esc the session stays "working" until its next event ([phase-0.md, question 1](phase-0.md#open-questions-for-the-owner)).
- **Flicker** when two subagents finish close together. A debounce of about two seconds. *24 Nov 2026:* card #47 uses 3 s, because the log counts whole seconds.
- **ttys are reused**, so the tty alone doesn't name a tab.

**What went wrong during the spike:**

1. Terminal, then iTerm2, refused Apple events with error −1712 while a dialog was open on screen. The owner closed it. Until then the subagent cases and the Esc case ran in a pseudo-terminal with a reset environment, and iTerm2 was only tested afterwards.
2. `/exit`, typed into Terminal by script in one burst, was completed to a different slash command. That command was cancelled at its first question.
3. A long prompt sent by Terminal's `do script` stayed in the input box without being sent. One more Return sent it.
4. Claude Code refuses a long plain `sleep` in a foreground command, so the subagents used a `pause` script. The model ignored "wait for it" until fork mode was off and `run_in_background` was named.
5. The first Cursor run didn't reach the log. The owner's second run did.
6. A wait loop with a broken condition cost one run of case c, which was repeated.
7. The first review rejected `profile-step.sh`. A failed `jq` or a work folder without an install could empty the settings file, a second install overwrote the backup, and the log could hold the first word of a prompt that started with `<`. All were fixed in the second round, and the rules for phase 3's installer above come from them.

## What was not done

- A session in the default profile through a terminal the spike drove. It was only seen in the owner's Cursor run.
- The `resume`, `clear` and `compact` sources of `SessionStart`.
- "Move to background and exit" in the exit dialog.
- Whether running sessions pick up a change to the settings file. *24 Nov 2026:* they do, for a project's settings ([on a real profile](#on-a-real-profile)).
- A look at whether a profile folder already describes its live sessions. The owner left it out, because it would mean reading other files in the profile folder.
- Background `workflow`, `teammate` and the other task types. Only `subagent` and `shell` were seen.
- Selecting the tab. The spike proved the handles match AppleScript, not the focus itself.
- Other terminals, such as tmux, Ghostty or WezTerm.
- Codex and other agents. Out of scope.

## For card #8

Card #8 writes `docs/spikes/phase-0.md` across all the spikes and corrects the spec. What this spike says about the spec:

**[docs/spec/feasibility.md](../spec/feasibility.md), "List Claude Code sessions":**

- "A small hook script reports session start, prompt, stop and "needs attention" events to the app. Each event carries the session id, the transcript file path and the working directory." **Confirmed.** "Needs attention" is `PermissionRequest` plus `Notification` with `permission_prompt`. A stop alone is not "finished": `Stop.background_tasks` decides.
- "Transcripts are local JSONL files, so titles and last activity can be read from disk." **Not tested here.** The spike confirmed the path and never read a transcript.
- "The app installs hook entries into your Claude settings file. It must do this carefully and reversibly." **Confirmed, with two additions.** The settings file can be a symlink shared by several profiles. Only a file that survives a two-space round trip byte for byte can be given back unchanged.

**"Three Claude accounts":**

- "each account has its own Claude Code profile folder. The app watches all of them and labels sessions by profile." **Confirmed.** The profile comes from `CLAUDE_CONFIG_DIR` or from `transcript_path`.
- "The hook has to be installed once per profile." **Contradicted** where profiles share one settings file by symlink, as every profile does on the test Mac. The hook is installed once per settings file, and one install reaches every profile that shares it. [docs/spec/decisions.md](../spec/decisions.md), row "Claude accounts", says the same: "The app reads every profile folder, labels each session with its profile and installs its hook once per profile."

**"Focus Terminal and iTerm2":**

- "The hook script runs inside the terminal, so it can read which app and which tab it is in (`TERM_PROGRAM`, `ITERM_SESSION_ID`, the tty)." **Confirmed, with a correction.** The hook has no tty of its own. The tty is the one of its parent, the `claude` process. Terminal's handle is the tty, because AppleScript doesn't show `TERM_SESSION_ID`. iTerm2's handle is the UUID after the colon in `ITERM_SESSION_ID`.
- "The app then selects that exact tab through AppleScript." **Not tested here.**

**"Focus VS Code and Cursor":** the hook tells the two apart by the bundle id or the ancestors, not by `TERM_PROGRAM`, which is `vscode` for both. Bringing the window forward was not tested.

**"How a session gets linked to its terminal":**

- Step 2, "The SessionStart hook runs a tiny script in that same terminal." **Partly.** It runs as a child of `claude`, without a tty of its own.
- Step 3, "The script sends the app: session id, folder, account, terminal app, tab identifier." **Confirmed.** The account is the profile folder. VS Code and Cursor have no tab identifier. Because ttys are reused, the script also sends the `claude` pid.
- Step 4, "Later hooks update the state: working, finished, waiting for permission." **Confirmed, with gaps.** "Finished" needs the `background_tasks` rule, and a denial or an Esc sends nothing.
- Step 5 was not tested.

**[docs/spec/decisions.md](../spec/decisions.md), the assumption "A hook can tell which terminal tab it runs in, on all four terminal hosts":** true for Terminal and iTerm2. VS Code and Cursor give the app, not the tab.

**"Biggest technical risks":**

- "**Terminal focus reliability** across four terminal hosts." The tab is identified for Terminal and iTerm2. Selecting it is still to prove.
- "**Hook formats change** as Claude Code and Codex evolve." Borne out. Since Claude Code 2.1.302 subagents run in the background by default, which changes how a session's end looks.

**[docs/spec/plan.md](../spec/plan.md), phase 0, "proven in a scratch project first and then in every profile":** every profile on the test Mac shares one settings file, so the one test on that file covered all of them.

**Still open:**

- A fallback for a turn that ends without an event: `PostToolUse` on every tool, the transcript's modification time, or a timeout.
- What the installer does with a settings file that doesn't survive the round trip, such as a hand-formatted one. *24 Nov 2026:* card #49 refuses it and shows the lines to add by hand ([phase-0.md, question 2](phase-0.md#open-questions-for-the-owner)).
- Whether running sessions pick up the installed hook without a restart. *24 Nov 2026:* yes for a project's settings, at the next prompt ([phase-0.md, question 3](phase-0.md#open-questions-for-the-owner)).
- Selecting the tab in Terminal and iTerm2, and the window in VS Code and Cursor.
- The events of "Move to background and exit", and the `resume`, `clear` and `compact` sources.
- Whether `workflow` and `teammate` entries look as the documentation says.
