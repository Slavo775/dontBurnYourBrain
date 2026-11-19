# Dev setup and quality

Tools, launch arguments, quality gates, the repository layout and the permissions the app asks for.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## What you need to build and run it

### Machine and accounts

- A Mac on a current macOS, and Xcode from the Mac App Store (free, large download). The current line is Xcode 27. The app targets the two latest major versions of macOS and iOS, today 26 and 27.
- An Apple ID. Enough to build and run on your own Mac for phases 0 to 5.
- Apple Developer Program, 99 USD per year. Not joined yet. It is needed for CloudKit, TestFlight and notarized builds, so join at phase 6 or when the first build goes to someone else, whichever comes first. The fee applies even though the app is free.
- An iPhone with Developer Mode switched on, for phase 6.
- Git repo on GitHub, public under the MIT license from the first commit.

### Command line tools

- `xcodebuild` comes with Xcode. Builds and runs tests from the terminal, so Claude Code can verify its own work.
- `brew install swiftlint swiftformat xcbeautify xcodegen`
- XcodeGen keeps the project definition in a small YAML file, which avoids merge pain in the generated Xcode project file and suits agent-written code.
- The generated project stays out of git, so a pull never updates it. Run `xcodegen generate` after every pull or branch switch that adds, removes or renames files, before you build in Xcode or with `xcodebuild`.

### Launch arguments

The app reads these arguments from the command line, so a check or a screenshot looks the same on every run. A value saved with `defaults write` is never used. They work only in the Dev build. A Release build ignores all of them: it runs a live clock, follows the system's appearance and opens the store on disk.

| Argument | What it does |
| --- | --- |
| `-DontBurnFixedTime 2026-01-15T09:41:30+01:00` | Freezes the clock at that instant, shown in the Mac's time zone. The value needs seconds and an offset, `Z` or `±hh:mm`. A malformed value is ignored, and the clock runs live. |
| `-DontBurnAppearance light` or `dark` | Sets the app's appearance for that launch, the compact panel included. It does not reach the menu bar item or its menu, which follow the system. Any other value follows the system. |
| `-DontBurnSampleData YES` | Runs on a store in memory, seeded with Acme, Globex and Personal: 3 workspaces, 5 projects (Reading under Personal is not time tracked), 3 blocks and 5 entries. One of them, the manual "Release checklist", lies a day earlier, so History has something to show. `true` and `1` work too. The store on disk is never opened. With `-DontBurnFixedTime`, the sample data is seeded around that time. |
| `-DontBurnTimerState running` | Puts the sample timer into one state, for the menu bar item. Works only with `-DontBurnSampleData`, with or without `-DontBurnFixedTime`. Values: `running` (Acme, 1:24 left), `ending` (Acme, 3:27 left), `paused`, `break` (4:12 left), `idle`, `untracked` (0:15 untracked), `long-name` (Acme under a very long name), and `short` (a six-minute block from launch, to watch on the live clock). An unknown value, or one longer than 16 bytes, is ignored. |

```sh
open DerivedData/Build/Products/Debug/DontBurn.app --args -DontBurnFixedTime 2026-01-15T09:41:30+01:00 -DontBurnAppearance dark -DontBurnSampleData YES
```

Without `-DontBurnSampleData`, the Dev build keeps its data in `~/Library/Application Support/io.github.slavo775.dontburn.dev/DontBurn.store`. The folder is named after the bundle identifier, so the Release app's data is never touched.

To start with an empty store on disk, such as for the "No workspaces yet" state, point the home folder at a new temporary folder: `open -g --env CFFIXED_USER_HOME=<temp folder> DerivedData/Build/Products/Debug/DontBurn.app`. The store is then created inside that folder. Remove the folder by its literal path when done.

How light and dark are checked is in "Checking a screen" of [../../rules/testing.md](../../rules/testing.md).

## From web development to Apple development

| You know | Here it is | Notes |
| --- | --- | --- |
| npm, package.json | Swift Package Manager, `Package.swift` | Built into Xcode. We will need very few dependencies. |
| React components, hooks, state | SwiftUI views, `@State`, `@Observable` | Same declarative idea: UI is a function of state. |
| TypeScript strict mode | Swift 6 language mode | The compiler also checks for data races between threads. |
| ESLint | SwiftLint | Rules in `.swiftlint.yml`, runs on every build and in the local check. |
| Prettier | SwiftFormat | Runs in a pre-commit hook. |
| Jest, Vitest | Swift Testing (`@Test`) | Unit tests for the shared package: timer engine, rounding, Jira payloads. |
| Playwright | XCUITest | A few smoke tests only. UI tests are slow. |
| Hot reload | Xcode Previews | Live preview of a single view with sample data. |
| SQLite or Postgres with an ORM | SwiftData | Models are plain Swift classes marked `@Model`. |
| .env secrets | Keychain | Never in code, never in the database. |
| GitHub Actions on Linux | A check command on your Mac; GitHub Actions only for releases | Tests on GitHub's Mac runners use up a private repository's free minutes ten times faster, so they run locally. See [../process/checks.md](../process/checks.md). |
| Deploy to Vercel | Archive, sign, notarize; TestFlight for iPhone | For personal use on the Mac, running from Xcode is enough at first. |

### Quality gates

1.  Compiler in Swift 6 mode, warnings treated as errors
2.  SwiftFormat and SwiftLint in a pre-commit hook
3.  Unit tests in the local check before every push; target 80% coverage on DontBurnCore, no target on views
4.  No tests on GitHub: the check command runs on your Mac and leaves its result on the commit. GitHub Actions run only releases
5.  One pull request per feature, reviewed by you before merge, even when an agent wrote it
6.  A short `CLAUDE.md` with build commands, architecture rules and the CloudKit model rules
7.  Interface text lives in a string catalog from day one, so more languages can be added later

### Repository layout

- `Packages/DontBurnCore` shared logic and models, with tests
- `Apps/Mac` menu bar app and Mac-only services
- `Apps/iOS` iPhone app, widget and Live Activity
- `Tools/dontburn-hook` the hook CLI
- `project.yml` XcodeGen definition
- `docs/` the spec, the design prototype and the process notes
- `.claude/` the agent flow: subagents in `agents/`, the owner's commands in `skills/`
- `.mcp.json` the Trello MCP server
- `rules/` rules for agents: `README.md` first, then the general rules and one file per role in `roles/`
- `scripts/` and `.githooks/` the check command and the git hooks

### Permissions the Mac app will ask you for

- **Notifications**, for timer and agent alerts. Asked at the first block start, never at launch
- **Automation**, once per terminal app, to select the right tab in Terminal and iTerm2. The permission belongs to the app that asks, so the Dev and the Release build each ask, because each is its own app. VS Code and Cursor needed none in phase 0, because the app reaches them through LaunchServices and sends them no Apple event
- **Calendars**, to read meetings (phase 5)
- **Launch at login**, optional

The app is not sandboxed, because it reads session files from other tools and scripts your terminals. It makes network calls only to Jira sites you add and to iCloud.

What agents may do on the Mac they work on, and what never enters the repository, is in [../../rules/safety-and-privacy.md](../../rules/safety-and-privacy.md).
