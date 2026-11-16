# Overview

What the app is for. A macOS app, with an iPhone companion later, for people who work across several organizations with many AI agent sessions open at once. Claude Code first, other agents later. Built for its maintainer first, then released free and open source for others. "Don't Burn Your Brain" is the working name.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Verdict: realistic, in Swift, built in stages

Every feature on the wish list can be built. Nothing depends on a private API. Three items carry caveats: VS Code and Cursor are focused at window level only, sessions outside Claude Code on this Mac are not listed, and both iCloud sync and builds for other people need a paid Apple Developer account.

React Native is the wrong tool here. Almost all the hard parts are native macOS glue, so the recommendation is Swift and SwiftUI with one shared code package for Mac and iPhone.

### The problem

Work for two employers and personal projects runs in parallel. Many terminal windows hold live Claude Code sessions, spread over several accounts. Context switches are expensive, time per organization is a guess, and Jira hours are reconstructed from memory.

### The product in one sentence

A menu bar app where you commit a block of time to one organization, see which agent sessions belong to it and jump to them in one click, and end the day with hours ready to log to Jira.

## Goals

1.  **Protect focus.** One active block at a time, a visible countdown, a clear signal when it ends.
2.  **Find the right terminal instantly.** Every agent session is listed with its project, state and a Focus button.
3.  **Know where the time went.** History per organization, project and Jira issue, with no manual bookkeeping.
4.  **Close the loop with Jira.** Tracked time becomes worklogs after a quick review.
5.  **Carry it on the phone.** Same data on iPhone through iCloud.
6.  **Work for other people too.** Nothing is tied to your own setup, and another developer can install it and be tracking time within minutes.

### Out of scope for version 1

- Teams and shared data. Every user keeps their own data in their own iCloud
- Automatic tracking of every app and window you touch
- Starting or controlling agent sessions from the app
- Any App Store release, for now. Other people get the Mac app as a signed download from the open-source project
- Android, Windows, web

### Design principles

- Two clicks or one hotkey to start a block
- Works fully offline; integrations are optional layers
- Never writes to Jira without showing you what it will send
- Secrets live in the Keychain, never in the synced database
- The app must reduce overhead. If a feature needs daily upkeep, it is cut.

> **One honest risk.** Building this is another project on a full plate. The plan is ordered so that the first two weeks already give you a daily-usable timer, and each later phase stands on its own. You can stop after any phase and still own something useful. Making it installable by other people is a separate last phase, so it never delays your own use.
