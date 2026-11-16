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
| [spec/dev-setup.md](spec/dev-setup.md) | Tools, quality gates, repository layout, permissions |
| [spec/decisions.md](spec/decisions.md) | What was decided and what each decision changes |

## The design

[design/prototype/index.html](design/prototype/index.html) holds the drawn screens. Open it in a browser. Several screens are live: the compact panel, Jira review and the Workspaces settings.

## The process: how work is done

| File | What it answers |
|---|---|
| [process/agent-flow.md](process/agent-flow.md) | The roles, the path of one task, statuses and the definition of done |
| [process/checks.md](process/checks.md) | The local check command, its receipt on the commit, and what runs on GitHub |
| [process/tasks.md](process/tasks.md) | Where tasks live, what each one carries and how the next phase gets its tasks |
| [process/releases.md](process/releases.md) | Versions, the Dev and Release builds side by side on Mac and iPhone, how a version is released, and what agents may do with each |
| [process/safety-and-privacy.md](process/safety-and-privacy.md) | What agents may touch on the maintainer's Mac, what never enters the repository, and what the app itself may do |

## Notes that come later

- `spikes/` gets the findings of the phase 0 spikes.
- `rules/` at the repository root gets the rules for agents in card 3.
