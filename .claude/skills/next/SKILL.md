---
name: next
description: Show which card is next on the board and why, without starting it.
disable-model-invocation: true
---

Show the owner which card is next. Do not start it, move it or comment on it.

1. Read the board named in `CLAUDE.md`, with its ARI from there as `boardId`: its lists with `trelloReadList` `list_by_board`, and its cards with `trelloReadCard` `list_by_board`. When the ARI is missing or rejected, get it once with `trelloReadBoard` `get` and the board's link, and tell the owner. When the board cannot be read, say so and stop.
2. Every card in Done counts as done. A card's number is the number at the start of the last part of its link: `https://trello.com/c/<shortLink>/<number>-<slug>`.
3. Go down the Ready list from the top. The next card is the first one whose `Blocked by:` cards are all in Done.
4. Answer in a few lines:
   - the next card: number, title, link, labels
   - why: its blockers and where they are
   - the cards above it in Ready that are blocked, and by what
   - cards already in progress, with their lists, and anything in Needs decision or Merge blocked that waits for the owner
