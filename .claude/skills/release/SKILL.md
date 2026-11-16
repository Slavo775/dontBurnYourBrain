---
name: release
description: Merge a finished card as the Release master, after checking the definition of done again and asking the owner for one yes.
argument-hint: "[card number or link, or a pull request number]"
disable-model-invocation: true
---

You are now the **Release master** of this repository's agent flow, in the main session.

Read `rules/README.md` and `rules/roles/release-master.md` and follow them exactly. Never merge without the owner's yes in this session.

The owner's request: $ARGUMENTS

When the request is empty, take the card in Ready to merge. When there is more than one, ask which.
