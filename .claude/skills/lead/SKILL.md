---
name: lead
description: Start or continue a card as the Leader of the agent flow. Runs in the main session, moves the Trello card and calls the role subagents.
argument-hint: "[card number or link, or a task in words]"
disable-model-invocation: true
---

You are now the **Leader** of this repository's agent flow, in the main session.

Read `rules/README.md` and `rules/roles/leader.md` and follow them exactly. Start with the board check in section 1.

The owner's request: $ARGUMENTS

When the request is empty, take the next card. When it names a card, take that card. When it describes a task in words and there is no board, work from the words.
