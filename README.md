# Don't Burn Your Brain

One menu bar for time, tasks and agent terminals.

A macOS app, with an iPhone companion later, for people who work across several organizations with many AI agent sessions open at once. You commit a block of time to one workspace, see which agent sessions belong to it and jump to the right terminal in one click, and end the day with hours ready to log to Jira.

**Status: early.** Nothing here is usable yet. The plan is in [docs/spec/plan.md](docs/spec/plan.md).

## What it will do

- Time blocks per workspace, with a countdown in the menu bar, breaks and a history
- A live list of Claude Code sessions, with a button that brings the right terminal tab forward
- Jira worklogs from tracked time, after a review where every number can still be changed
- Meetings from the calendars the Mac already keeps, and a plan for the day around them
- The same data on the iPhone through iCloud

The full description is in [docs/spec](docs/spec), and the drawn screens are in [docs/design/prototype](docs/design/prototype).

## Build

You need a Mac on macOS 26 or later, Xcode 27 selected as the active developer directory, and the tools from Homebrew:

```sh
brew install swiftlint swiftformat xcbeautify xcodegen
```

After cloning, run `./scripts/bootstrap` once. It sets up the git hooks. `./scripts/check` then runs format, lint, build, tests and a privacy scan in one go, and it also runs before every push.

The Xcode project is generated from `project.yml` and is not in git. From the repository root:

```sh
# Generate DontBurn.xcodeproj
xcodegen generate

# Build the app and the hook tool
xcodebuild -project DontBurn.xcodeproj -scheme DontBurn -configuration Debug \
  -derivedDataPath DerivedData build | xcbeautify

# Run the tests of the shared package
swift test --package-path Packages/DontBurnCore

# Start the development build. It appears in the menu bar, with a Quit item
open DerivedData/Build/Products/Debug/DontBurn.app
```

No Apple developer account is needed. The build is signed to run locally.

The Debug build is a separate app, "Don't Burn Your Brain Dev", with its own bundle identifier (`io.github.slavo775.dontburn.dev`). Its data, settings and permissions stay apart from a Release build on the same Mac.

## How work is done here

Most of the code is written by AI agents and reviewed by a person. [docs/process](docs/process) describes the agent flow, the local checks, the tasks and the releases. The rules the agents follow, safety and privacy among them, are in [rules](rules). Work on a task starts with `/lead` in Claude Code, and `/release` merges it after the maintainer's yes.

## License

MIT. See [LICENSE](LICENSE).
