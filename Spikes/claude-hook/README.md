# Spike: a Claude Code hook reports a session

Card #5. Throwaway code that answers one question: what can a hook that Claude Code runs tell the app about a session? It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

| File | What it is |
|---|---|
| `spike-hook.sh` | The hook. It reads the event JSON from standard input and appends one line to `events.jsonl` next to itself: the event's field names, the ids and paths, the terminal's environment variables, and the chain of parent processes with their ttys. It never writes prompt text, replies or transcript content, and it always exits 0. Needs `jq`. Without it the hook does nothing |
| `settings.local.json` | The scratch project's settings: the spike's hook on every event the spike looks at, with a 5-second timeout, and two allowed commands that only wait |
| `pause` | `./pause 30` waits 30 seconds. Claude Code refuses a long plain `sleep`, so the subagents in steps 9 to 11 call this instead |

## Set up a scratch project

Never inside this repository and never in a real profile's settings. From the repository root:

```sh
SCRATCH=$(mktemp -d -t dontburn-spike)
mkdir -p "$SCRATCH/project/.claude"
cp Spikes/claude-hook/spike-hook.sh "$SCRATCH/"
cp Spikes/claude-hook/pause "$SCRATCH/project/"
cp Spikes/claude-hook/settings.local.json "$SCRATCH/project/.claude/"
echo "$SCRATCH"
```

The log is `$SCRATCH/events.jsonl`. The hook is found through `$CLAUDE_PROJECT_DIR/../spike-hook.sh`, so the settings file needs no absolute path.

**Check that the hook can never hold a session up.** Each call must print `exit=0`. The first two add an `invalid-input` line each to the log. The third runs without `jq` and adds nothing:

```sh
printf ''        | CLAUDE_PROJECT_DIR="$SCRATCH/project" "$SCRATCH/spike-hook.sh"; echo "exit=$?"
printf 'not json' | CLAUDE_PROJECT_DIR="$SCRATCH/project" "$SCRATCH/spike-hook.sh"; echo "exit=$?"
PATH=/nonexistent /bin/bash "$SCRATCH/spike-hook.sh" </dev/null; echo "exit=$?"
jq -c '{event, bytes}' "$SCRATCH/events.jsonl" && rm "$SCRATCH/events.jsonl"
```

## Start Claude Code in a terminal

Open a new window in the terminal app under test and run, with the folder `echo` printed above:

```sh
cd <scratch folder>/project
command claude --model haiku --setting-sources project,local --permission-mode default
```

- `command` skips a shell function or alias named `claude`.
- Claude Code uses the profile that `CLAUDE_CONFIG_DIR` names, or `~/.claude` when it is not set. Put `CLAUDE_CONFIG_DIR=<profile folder>` in front of the command to choose one.
- `--setting-sources project,local` leaves the hooks and plugins of the user's own settings out of this run.
- `--permission-mode default` makes Claude Code ask before it writes a file. Without it a session can start in auto mode, and step 3 shows no prompt.
- On the first start in a folder Claude Code asks whether you trust it. The preselected answer is "No, exit". Choose "Yes, I trust this folder".
- When text is typed by a script, send the text and the Return key separately. A slash command typed in one burst can be completed to a different command.

## Steps and what the log shows

Read the log after each step:

```sh
jq -c '{at, event, source, reason, notification_type, tool_name, agent_id, agent_type, tool_status, prompt_kind,
  bg: (.background_tasks | if . == null then null else map(.type + "/" + .status) end)}' "$SCRATCH/events.jsonl"
```

And what the terminal tells the hook:

```sh
jq -c 'select(.event == "SessionStart") | {session_id, cwd, transcript_path, tty, env, comm: [.ancestors[].comm]}' "$SCRATCH/events.jsonl"
```

| Step | Do | The log shows |
|---|---|---|
| 1 | Start Claude Code as above | `SessionStart` with `source: startup`, `session_id`, `cwd`, `transcript_path` and `model`. `tty` is the tab's tty, `env` has `TERM_PROGRAM` and the terminal's own session id, and `ancestors` runs from the hook through `claude` and the shell to the terminal app |
| 2 | Type `Reply with the single word ok.` | `UserPromptSubmit` with `prompt_kind: typed`, then `Stop` with `background_tasks: []`. One second later there can be a `SubagentStop` with an empty `agent_type` and no `SubagentStart`: an agent Claude Code runs for itself |
| 3 | Type `Use the Write tool to create a file named note.txt that contains the word hi.` Do not type for ten seconds, then answer "1. Yes" | `UserPromptSubmit`, `PermissionRequest` with `tool_name: Write` at once, `Notification` with `permission_prompt` about 6 seconds later, and `Stop` after the answer |
| 4 | Type nothing for 70 seconds | `Notification` with `idle_prompt`, 60 seconds after the last `Stop` |
| 5 | Ask for `second.txt` the same way and answer "3. No" | `UserPromptSubmit`, `PermissionRequest`, `permission_prompt`, and then nothing: no `Stop` |
| 6 | Type `Count from 1 to 400, one number per line, no other text.` and press Esc after two seconds | `UserPromptSubmit` and then nothing: no `Stop` |
| 7 | Type `/exit` | `SessionEnd` with `reason: prompt_input_exit`. A closed tab, which sends SIGHUP to `claude`, gives `SessionEnd` with `reason: other` |
| 8 | Start Claude Code again as in step 1 | `SessionStart` with a new `session_id`. The folder is trusted now |
| 9 | Type `Start two subagents with the Agent tool in one message, both with run_in_background set to true and subagent_type general-purpose. The first runs the Bash command ./pause 30 and then replies done-one. The second runs the Bash command ./pause 45 and then replies done-two. Tell them not to run those commands in the background. After launching them, end your turn at once without waiting for them.` and wait a minute | `UserPromptSubmit`, then per subagent `PreToolUse`, `SubagentStart` and `PostToolUse` with `tool_status: async_launched`. Then `Stop` with two `subagent/running` entries in `background_tasks`. About 30 seconds later `SubagentStop` of the first, `UserPromptSubmit` with `prompt_kind: tag:task-notification`, and `Stop` with one entry. Then the same for the second, ending with `Stop` with `background_tasks: []` |
| 10 | Type `Start one subagent with the Agent tool, subagent_type general-purpose, in the background. It runs the Bash command ./pause 60 in the foreground and then replies done. After launching it, end your turn at once without waiting for it.` Ten seconds after it answers, type `/exit` and choose "1. Exit and stop tasks" | `Stop` with one `subagent/running` entry. The exit dialog fires nothing. Then `SessionEnd` with `reason: prompt_input_exit`, and no `SubagentStop` for the subagent that was still working. Its `./pause` is gone afterwards |
| 11 | Start Claude Code as in step 1, with `CLAUDE_CODE_FORK_SUBAGENT=0` in front. Type `Call the Agent tool once with subagent_type general-purpose and with the parameter run_in_background set to false. The subagent runs the Bash command ./pause 20 in the foreground and then replies done. When it returns, reply with its answer.` | `UserPromptSubmit`, `PreToolUse` with `run_in_background: false`, `SubagentStart`, then nothing for 20 seconds, `SubagentStop`, `PostToolUse` with `tool_status: completed`, and one `Stop` |

Steps 9 to 11 do not depend on the terminal app, so they need running in one terminal only.

## VS Code and Cursor

The same scratch folder, by hand:

1. `open -a "Visual Studio Code" <scratch folder>/project`, or File, Open Folder in VS Code.
2. Open the integrated terminal (Terminal, New Terminal).
3. Run the command from "Start Claude Code in a terminal". Answer the trust prompt if it shows.
4. Type `Reply with the single word ok.`, wait for the answer, then `/exit`.
5. Close the window, and repeat steps 1 to 4 in Cursor with `open -a Cursor <scratch folder>/project`.

Then compare what the two editors told the hook:

```sh
jq -c 'select(.event == "SessionStart") | {at, tty, env, env_names, comm: [.ancestors[].comm]}' "$SCRATCH/events.jsonl"
```

## Clean up

Stop every `claude` you started with `/exit`, close the windows you opened, and remove the scratch folder with `rm -rf "$SCRATCH"`. Claude Code keeps the transcripts of these sessions in the profile it ran under, like any other session.
