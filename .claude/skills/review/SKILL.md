---
name: review
description: Run the Reviewer alone on a pull request the owner names, and post its verdict on the pull request.
argument-hint: "<pull request number>"
disable-model-invocation: true
context: fork
agent: reviewer
background: false
---

Review pull request $ARGUMENTS on its own, as `rules/roles/reviewer.md` describes under "Alone with `/review`". Do not touch the Trello board.
