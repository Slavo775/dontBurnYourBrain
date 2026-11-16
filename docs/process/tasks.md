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

Branches are named after the card: `feat/<number>-<short-slug>`, such as `feat/10-timer-engine`.

## Phases and when their cards are written

Only the current phases have cards. A later phase gets its cards when the one before it is nearly done, because spikes and daily use change the details.

At the end of each phase the Leader:

1. checks the phase's exit line in the plan with the maintainer
2. corrects `docs/spec` where reality turned out different
3. writes the cards of the next phase with the maintainer, in the format above

Reports and requests from other people arrive from phase 8 on as GitHub issues. Each accepted one becomes a card.

## The first 16 cards

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

Phase 1 ends when the maintainer runs a full working day on the app.
