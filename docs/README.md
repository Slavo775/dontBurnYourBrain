# Docs

Everything an agent or a person needs before changing code. These files are the working copy: when behaviour changes, they change in the same pull request.

## The spec: what to build

| File | What it answers |
|---|---|
| [spec/overview.md](spec/overview.md) | What the app is for, its goals and what is out of scope |
| [spec/features.md](spec/features.md) | Every feature with its priority and phase, a normal day, and the rules about time |
| [spec/feasibility.md](spec/feasibility.md) | How each feature can be built, with its caveats and risks |
| [spec/tech-stack.md](spec/tech-stack.md) | Why Swift, the architecture, and the data model |
| [spec/design.md](spec/design.md) | Every screen and how it behaves |
| [spec/plan.md](spec/plan.md) | The phases, from setup to a release for other people |
| [spec/dev-setup.md](spec/dev-setup.md) | Tools, launch arguments, quality gates, repository layout, permissions |
| [spec/decisions.md](spec/decisions.md) | What was decided and what each decision changes |

## The design

[design/prototype/index.html](design/prototype/index.html) holds the drawn screens. Open it in a browser. Several screens are live: the compact panel, Jira review and the Workspaces settings.

## The process: how work is done

| File | What it answers |
|---|---|
| [process/agent-flow.md](process/agent-flow.md) | The roles, the path of one task and the statuses |
| [process/checks.md](process/checks.md) | The local check command, its receipt on the commit, and what runs on GitHub |
| [process/tasks.md](process/tasks.md) | Where tasks live, what each one carries and how the next phase gets its tasks |
| [process/releases.md](process/releases.md) | Versions, the Dev and Release builds side by side on Mac and iPhone, and how a version is released |
| [process/safety-and-privacy.md](process/safety-and-privacy.md) | A pointer to the rule file, and what was done because the repository is public from the start |

The rules that bind agents are in `rules/` at the repository root: [../rules/README.md](../rules/README.md) first, then the general rules (code style, testing, git, safety and privacy, releases, the definition of done and the lessons) and one file per role in `roles/`. Where a rule and a page here cover the same subject, the rule file is the only copy and the page points at it. The subagents and the owner's commands are in `.claude/`.

## Spike notes

The findings of the phase 0 spikes: one summary across them, and one note per spike.

| File | What it answers |
|---|---|
| [spikes/phase-0.md](spikes/phase-0.md) | What the three spikes found together: what works, what does not, what phase 3 can rely on, how sure each result is, and the open questions for the owner |
| [spikes/claude-hook.md](spikes/claude-hook.md) | What a Claude Code hook tells the app about a session, its state, its terminal tab and its profile, and how the hook goes into a profile's settings and out again without a trace |
| [spikes/terminal-focus.md](spikes/terminal-focus.md) | Whether a command brings the exact tab of a session forward in iTerm2 and Terminal, how often and how fast, which handle each app uses, the awkward cases, and whose permission the commands need |
| [spikes/editor-focus.md](spikes/editor-focus.md) | Whether a command brings forward the VS Code or Cursor window that holds a session, which command, how often and how fast, the card's six cases and how sure each result is, what phase 3 should do with a subfolder, and why an unwanted window is costly |
