# Tasks

Tasks are cards on the maintainer's Trello board, and the board's lists are their statuses. Agents read and move the cards through Trello's official MCP server, which is set up for this repository in `.mcp.json`. Every step leaves a comment on the card, so the board is the full record of what happened.

Someone without access to the board can still work here: give the task in the chat, and the agent flow works the same without the board. See [agent-flow.md](agent-flow.md).

## The board

| List | Meaning |
|---|---|
| Backlog | Written, not ready to start yet |
| Ready | Can be pulled |
| In design, In development, In testing, In review, Changes requested, In docs | Work in progress, one list per step of the flow |
| Needs decision | Waiting for the maintainer |
| Ready to merge, Merge blocked | The Release master's lists |
| Done | Merged |
| Cancelled | Dropped, with the reason in a comment |

Labels name the phase (`Phase 0`, `Phase 1`, …) and mark spikes (`Spike`).

## Which card is next

The top card in Ready whose `Blocked by` cards are all in Done. `/next` shows it and says why. Cards of one phase are created in the order they must happen, so the order of the list is the order of the work.

## What every card carries

- A title that names the outcome.
- Its labels.
- A description with:
  - the goal in one sentence
  - `Blocked by:` and `Blocks:` lines, with card numbers such as `#5`, or `none`
  - where the spec describes it
  - what is in scope and what is not
  - the done-when list
  - how to verify it
  - notes and known pitfalls
- A checklist named `Checklist`: the steps, ending with the check command and a pull request.
- From the first step on: a comment per step, and the link to the pull request.

Branches are named after the card, such as `feat/10-timer-engine`. The exact form is in [../../rules/git.md](../../rules/git.md).

## Phases and when their cards are written

Only the current phases have cards. A later phase gets its cards when the one before it is nearly done, because spikes and daily use change the details.

What the Leader does at the end of each phase is in [../../rules/roles/leader.md](../../rules/roles/leader.md) under "End of a phase".

Reports and requests from other people arrive from phase 8 on as GitHub issues. Each accepted one becomes a card.

## The cards of each phase

The cards of phases 0 to 3, in the order they were written. Cards with other numbers are follow-ups, work on the flow itself, or wait in Backlog. The board has them all.

### Phase 0: setup and risk spikes

1. One command that checks everything, with a receipt
2. The project's own agent flow
3. Rules for agents, with the lessons carried over
4. Menu bar item that shows a clock
5. Spike: a Claude hook reports a session
6. Spike: bring the exact tab forward in iTerm2 and Terminal
7. Spike: bring the right window forward in VS Code and Cursor
8. Write down what the spikes found

Cards 1 and 2 are done without the flow, because it does not exist yet. From card 3 on, the Leader runs them.

Phase 0 ends when the app builds and runs from Xcode and from the command line, and the focus trick is proven or its limits are known.

### Phase 1: time blocks you can use every day

9. Data model for workspaces, blocks and entries
10. Timer engine
11. Workspaces in Settings
12. Menu bar countdown
13. Compact panel with the four quick actions
14. Quick start in the panel
15. Notifications and sounds
16. Today list and simple history
17. Release v0.1.0 beside the Dev build

Phase 1 ends when the maintainer runs a full working day on the Release build from card 17. It ended on 19 November 2026, on v0.1.0.

### Phases 2 and 3, side by side

The two phases run side by side, in the order of the Ready list. As always, the next card is the top one whose `Blocked by` cards are done.

45. The plan and CLAUDE.md match the decisions on projects, sessions and trackers

### Phase 3: agent sessions and terminal focus

46. Projects in Settings: name, folders and whether time is tracked
47. Session states from hook events, in the shared package
48. The hook tool reports a session's events to the running app
49. Settings, Sessions: install and remove the hook, with a clean uninstall
50. Expanded panel with the session list, also when no block runs
51. Focus brings a session's exact tab forward in Terminal and iTerm2
52. Focus brings a session's window forward in VS Code and Cursor
53. The app tells you when an agent waits for you
54. Jump to a session from the keyboard
55. Release the version with sessions, and the owner uses it for a week
56. Spike: a Chrome profile for each workspace, and its window brought forward

Phase 3 ends when the maintainer has used the Release build from card 55 for a week and stops hunting for terminal windows.

### Phase 2: focus rhythm and history

57. Focus rhythm in the timer engine: planned focus intervals and breaks
58. Rhythm in the panel, the menu bar and Settings
59. Idle time: the app asks what to do with time away from the Mac
60. History by week and month, totals per project, split an entry, export to CSV
61. Command bar on a global shortcut
62. The app starts when the owner logs in, if he wants
63. Release the version with rhythm, history and the command bar

Phase 2 ends when the maintainer has used the Release build from card 63 for a few working days and said what got in his way.

Whichever of cards 55 and 63 comes first takes the next version, and the other takes the one after.
