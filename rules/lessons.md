# Lessons

What went wrong, and the rule that came from it. The Leader reads this file at the start of every card.

## When an entry is written

The Leader writes one after a bad outcome: two or more failed rounds, a decision the owner corrected, a blocked merge, or a cancelled task.

An entry never goes onto the card's own branch, because a change to `rules/` there would need new verdicts, and a cancelled card's branch never merges. The Leader shows the entry to the owner in the chat and in a comment on the card. It is then committed in a pull request of its own, together with the rule change when the owner accepted it. That is a task like any other: a card of its own when there is a board, and a branch named as `rules/git.md` says.

## The entry format

```
## <date> · <short title> · <status>

- **What happened:** <facts, with the card and the pull request>
- **Root cause:** <why, not who>
- **Proposed change:** <the rule, and the file it goes into>
```

## The three statuses

| Status | Meaning |
|---|---|
| `proposed` | Written by the Leader and waiting for the owner, in the chat or in an open pull request. Not binding yet |
| `accepted` | The owner said yes. The rule is written into the file named, through a pull request, and is binding |
| `declined` | The owner said no. The entry stays, with his reason, so it is not proposed again |

Nothing in a rule or an agent changes without the owner's yes.

## Carried over from the reference flow

These were learned in the reference flow before this project started. All are `accepted`, and each is already written where the table says.

| Rule | Written in |
|---|---|
| Stop only the processes you started, by the process ID you recorded. Never a name pattern | `safety-and-privacy.md`, `testing.md`, `roles/developer.md`, `roles/designer.md`, `roles/tester.md` |
| Anything that deletes or rewrites data runs against a throwaway store | `testing.md`, `safety-and-privacy.md` |
| A pull request that conflicts only because another merged first gets `main` merged in with a normal merge commit. No rebase, no force-push. Not a failed round | `git.md`, `roles/release-master.md`, `roles/leader.md` |
| A blocked task whose session has stopped can be taken over by any Leader, in its own worktree | `roles/leader.md` |
| Before work starts, list the open pull requests and the files they change | `roles/leader.md` |
| A skipped test is not a pass. Tests run with the check command's settings | `testing.md`, `definition-of-done.md` |
| A card that touches a shared element lists that element's documented limits | `roles/leader.md` |
| A new dependency is named on the card with its license and the reason, and the Reviewer checks both | `roles/leader.md`, `roles/reviewer.md`, `safety-and-privacy.md` |
| Light and dark are each checked on a fresh launch with the mode already set | `testing.md`, `roles/designer.md` |
| A look the design docs do not show needs the owner's reference first, and the proposal is shown as a whole screen | `roles/leader.md`, `roles/designer.md` |
| A screen test performs at least one real interaction | `testing.md` |
| Every new way into the app from outside limits the size and checks the shape of what it reads | `safety-and-privacy.md`, `roles/reviewer.md` |

## Entries

## 2026-11-16 · Trying a rule change before the Tester · accepted

- **What happened:** card #3 (PR #6) needed three test rounds. The Tester rejected the new rules twice, and the Reviewer then found three more gaps of the same kind. Rules contradicted each other, a command did not prove what its rule claimed, and a new procedure, taking a card over, was not followed through in the other role files.
- **Root cause:** the Leader sent new rules to the Tester without running the commands they name, and without following a new procedure through every role file it touches.
- **Proposed change:** one rule in `rules/roles/leader.md`, section 8 "Changing the flow".

## 2026-11-17 · Clicking the menu bar item · accepted

- **What happened:** on card #4 (PR #7), two synthetic mouse clicks meant for the app's own menu bar item landed in other apps on the maintainer's Mac. One hit the built-in display where the cursor had rested, the other a browser's tab bar on another display. The last test round used `AXPress` only and had no stray input.
- **Root cause:** no rule said how to interact with a menu bar item. On this macOS, status items are hosted by `MenuBarAgent`, their positions span several displays, and the owner's live mouse moves under the clicks. So clicks aimed at coordinates miss.
- **Proposed change:** one rule in `testing.md`, "Checking a screen".

## 2026-11-17 · Typing into a terminal by script · accepted

- **What happened:** on card #5 (PR #8), an agent sent `/exit` into a Terminal tab with `do script`, which sends the text and Return at once. Claude Code completed it to a different slash command, which offered to change a real profile's settings. The agent cancelled it. Later, Terminal and iTerm2 stopped answering Apple events (error −1712) while a dialog was open on screen.
- **Root cause:** no rule said how an agent types into a terminal by script, or what an Apple event timeout means.
- **Proposed change:** two rules in `safety-and-privacy.md`, "Permissions and the system".

## 2026-11-17 · A profile's settings file can be shared · accepted

- **What happened:** on card #5 (PR #8), the owner approved changing one profile's `settings.json`. It was a symlink to another profile's file, which every profile on the Mac shares. The spike's precheck stopped, and the owner then approved the shared file itself.
- **Root cause:** the rules treat each profile's settings file as its own.
- **Proposed change:** one rule in `safety-and-privacy.md`, "Claude Code profiles and other tools".

## 2026-11-17 · Removing a temporary folder · accepted

- **What happened:** on card #5 (PR #8), Claude Code's safety check refused an agent's `rm -rf "$WORK"`, and nothing ran. The folder was then removed by its literal path.
- **Root cause:** no rule said how an agent removes the temporary folders the rules ask for.
- **Proposed change:** one rule in `safety-and-privacy.md`, "Builds and data", which every role reads.

## 2026-11-18 · Making the Dev app frontmost while testing · accepted

- **What happened:** on card #11 (PR #23), the Tester made the Dev app frontmost with `NSRunningApplication.activate()` so it could type into the app by script. The owner's live keystrokes then landed in the app's name field and never reached the app the owner was using. The data was in memory only. In the same round, a menu helper that searched MenuBarAgent's accessibility tree too deeply pressed one of the app's own buttons and created a workspace in the Dev store. The store was restored from a backup.
- **Root cause:** no rule said that an agent must not activate the app, even though typing with `CGEventPostToPid` and accessibility focus work without activating it. The app was also started with plain `open`, which brings it forward. "Checking a screen" names the path window → group → item, but it does not say that a deeper search finds the app's own controls.
- **Proposed change:** in `testing.md`, "Running the Dev build", which the Tester, the Developer and the Designer all read: the app starts with `open -g`, and it is never made frontmost, with one exception, closed right after, for a control that brings it forward by design, such as Settings…. In "Checking a screen", the menu bar is searched exactly three levels deep.

## 2026-11-18 · Owner's keystrokes landing in the open panel · accepted

- **What happened:** on card #14 (PR #28), the Tester reopened the compact panel several times during a block-end test while the maintainer was working. The sample block went "On a break" with no key sent by the Tester. A "b" the maintainer typed in another app most likely went to the panel, and that keystroke was lost from the app he was using. The data was the in-memory sample.
- **Root cause:** by the card #13 design, the panel takes keys as soon as it opens, without bringing the app forward. "Running the Dev build" forbids making the app frontmost, but says nothing about the panel, which takes the keyboard without being frontmost.
- **Proposed change:** one rule in `rules/testing.md`, "Running the Dev build", which the Tester, the Developer and the Designer all read.

## 2026-11-18 · Screenshots by region · accepted

- **What happened:** on card #16 (PR #31), the Tester twice took a region screenshot (`screencapture -R`) meant for the Dev app's window. Both times it captured whatever was on the maintainer's screen at those coordinates instead. The Tester deleted both files from its scratchpad at once and switched to `screencapture -l <window ID>`. Neither file reached the screenshots folder, the repository or the pull request.
- **Root cause:** "Checking a screen" says to take screenshots with `screencapture`, but not how. A region is a place on the screen, not a window. The Dev app is never frontmost, so anything else can cover that region.
- **Proposed change:** one rule in `rules/testing.md`, "Checking a screen", which the Tester, the Reviewer and the Designer read.

## 2026-11-19 · Keys while the owner works, and a locked screen · accepted

- **What happened:** on card #44 (PR #39):
  - The Designer opened the compact panel for screenshots, and the running sample block came out paused with no key sent by the Designer. Most likely a "p" the maintainer typed in another app landed in the panel, and that keystroke was lost from the app he was using. Only the in-memory sample data was affected, and the run was discarded.
  - The Tester sent five keys with `CGEventPostToPid` right after a menu bar lookup failed. No panel was open, and the app beeped five times. Nothing changed.
  - The maintainer's screen was locked twice during the Tester's runs, for about a quarter of an hour each time. The menu bar item could not be reached, and the Tester read what happened from the system log.
- **Root cause:** "Running the Dev build" says to open the panel only for the check that needs it. It does not say to confirm the panel is open before a key is sent, to send a check's keys at once, or what to do when the menu bar item cannot be reached. A key sent with no panel open goes nowhere useful. The longer the panel stays open, the more of the maintainer's typing it can take.
- **Proposed change:** one rule in `rules/testing.md`, "Running the Dev build", which the Tester, the Developer and the Designer read.
