# Releases, versions and build variants

How the app is versioned, and how a development build and the maintainer's daily copy live side by side on one Mac and one iPhone. The rules for agents are in [../../rules/releases.md](../../rules/releases.md).

## Versions

- **One place.** `MARKETING_VERSION` in `project.yml` is the version for humans, such as `0.3.0`. Nothing in the code repeats it. The app reads it from its bundle, and the hook tool from the Info.plist built into its binary.
- **`main` carries the version being worked towards.** After `v0.1.0` is released, `main` moves to `0.2.0`.
- **Which number moves:**

| Version | When |
|---|---|
| `0.1.0` | End of phase 1: the first build the maintainer uses for a whole working day |
| `0.x.0` | The end of each later phase |
| `0.x.y` | A fix to a released version |
| `1.0.0` | The public release in phase 8 |

- **The build number** is `CURRENT_PROJECT_VERSION`. It is `1` in development builds. The release script sets it to the number of commits on `main` (`git rev-list --count HEAD`, on a full clone). It only ever grows, which TestFlight requires.
- **Mac and iPhone always share version and build**, because they share data through iCloud.
- **The app says what is running.** Settings, General shows version, build and variant: "Version 0.1.0 (1) · Dev · 1a2b3c4" in Dev, "Version 0.1.0 (412) · Release" in Release. Only Dev shows the short commit hash. `dontburn-hook --version` prints `dontburn-hook 0.1.0 (1)`.
- **A release is a git tag** `vX.Y.Z` on `main`, annotated, with a section in `CHANGELOG.md` written from the Conventional Commits since the previous tag.

## Build variants

| | Dev | Release | Beta (from phase 8) |
|---|---|---|---|
| Build configuration | Debug | Release | Release |
| Bundle identifier | `io.github.slavo775.dontburn.dev` | `io.github.slavo775.dontburn` | the Release identifier |
| Name on screen | Don't Burn Your Brain Dev | Don't Burn Your Brain | Don't Burn Your Brain |
| Who runs it | Agents and Xcode | The maintainer, every day | The maintainer and early testers |
| Data | Sample data (Acme, Globex, Personal) or throwaway | Real | Real |
| iCloud environment | Development | Production | Production |
| Global shortcuts | Off by default, and never on by default in a Debug build | On by default, as set by the user | On, as set by the user |
| Launch at login | Never registers. The switch is hidden, and `-DontBurnLoginItem` shows it only for a check | Off until the user switches it on | Off until the user switches it on |
| Gets updates from | Xcode | `./scripts/install-release`, later Sparkle | Sparkle's beta channel |

Because the identifiers differ, macOS treats Dev and Release as two separate apps: separate data folders, settings, Keychain items, permissions and notifications. Both can sit in the menu bar at the same time.

### Telling Dev from Release

- **The menu bar item.** Dev draws a small "DEV" after its label, and VoiceOver reads ", Dev build" after the label. Release shows nothing extra. See [Menu bar item](../spec/design.md#menu-bar-item).
- **The icon.** Dev uses `AppIcon-Dev`, an orange placeholder in `Apps/Mac/Assets.xcassets`. Release has no icon yet.
- **Settings, General**, as under [Versions](#versions).

### How the build knows its variant

- `project.yml` sets `APP_VARIANT` per configuration: `Dev` for Debug, `Release` for Release.
- A build phase, "Variant and commit", writes it into the built Info.plist as `DontBurnVariant`. In Dev it also writes `DontBurnCommit`, the short git hash. Release, or a build without git, carries no `DontBurnCommit`.
- The phase lists the built Info.plist as an input file, so Xcode runs it after it has written that file. Before card 61 an incremental build could write the Info.plist again after the phase, which dropped `DontBurnVariant`, and the Dev build read as Release. Card #70 stays open for that bug's own checks.
- `BuildInfo` in `DontBurnCore` reads the version, build, variant and commit from the bundle. A missing or unknown variant counts as Release. So the command bar's shortcut does not trust the variant alone: a Debug build never turns it on by default ([design.md](../spec/design.md#shortcuts-1)). The hook installer and the login item go by `BuildInfo.isDevBuild`, in `Apps/Mac/BuildInfo+Current.swift`, which counts every Debug build as Dev, so no Debug build writes into a real profile or registers a login item ([design.md](../spec/design.md#start-at-login)).
- `project.yml` names both bundle identifiers once, as `DONTBURN_RELEASE_BUNDLE_IDENTIFIER` and `DONTBURN_DEV_BUNDLE_IDENTIFIER`, which is the Release one plus `.dev`. The app takes one per configuration. The hook tool takes its own, the Release one plus `.hook`, and carries both in its Info.plist as `DontBurnReleaseBundleIdentifier` and `DontBurnDevBundleIdentifier`, so it reaches either build whichever configuration built it.

### Everything with a name outside the app follows the bundle identifier

So that Dev and Release never answer each other's messages:

- the data folder (already in `StoreLocation`)
- the channel the hook tool talks to: `Hook.socket` in the data folder, such as `~/Library/Application Support/io.github.slavo775.dontburn.dev/Hook.socket` for Dev
- the URL scheme: `dontburn://` for Release, `dontburn-dev://` for Dev
- Keychain service names, defaults suites and the logging subsystem
- notification names and anything registered with launchd, such as the login item, which `SMAppService.mainApp` registers for the app itself, by its bundle identifier

The hook tool sends to Release by default. Only two forms name a target:

- **No arguments.** `DONTBURN_TARGET` decides, `dev` or `release`. Unset or empty means Release.
- **Exactly `--target dev` or `--target release`.** It wins over `DONTBURN_TARGET`.

Anything else sends nothing, so an event never reaches the other build by mistake: another spelling such as `--target=dev` or `-t dev`, `--target` without a name, an unknown name, or an extra or repeated argument. Hooks installed in the maintainer's real Claude Code profiles therefore always reach his daily copy. Dev is tested from a scratch project.

The app carries the hook tool inside its bundle, at `Contents/Helpers/dontburn-hook`, and Settings, Sessions writes that absolute path into a settings file. The Release build writes it with no target. The Dev build writes `--target dev`, and installs only inside the stand-in folder named by `-DontBurnStandInHome`, never into a real profile ([dev-setup.md](../spec/dev-setup.md#launch-arguments)). A hook names the app where it stood at the install, so a Release app that is moved later leaves a hook that runs a missing command. Backlog card #74 covers that.

## On the Mac

**Until phase 8, without a paid Apple developer account:**

The maintainer runs `./scripts/install-release` when a version is tagged, or when he wants to try `main` in his daily copy (agents: see [../../rules/releases.md](../../rules/releases.md)). It:

1. Refuses a dirty tree, a detached HEAD or any branch but `main`. A shallow clone fetches its full history first, and the script stops if it stays shallow.
2. Sets the build number to `git rev-list --count HEAD`. The version stays as `project.yml` has it.
3. Runs `xcodegen generate` and builds Release into a temporary folder, removed when the script ends, so no second copy of the daily app is left in the checkout.
4. Signs with the Personal Team when the git-ignored `Local.xcconfig` in the repository root has a line `DEVELOPMENT_TEAM = <team ID>`. Without it, the app is signed to run locally, and the script warns that macOS may ask for permissions again after each update. The Personal Team avoids that.
5. Refuses to replace an app in `/Applications` that has another bundle identifier, or none.
6. Quits the running Release app politely, by its bundle identifier, and waits up to 10 seconds. It never forces. The first time, macOS asks to let the terminal control the app (Automation). Denied, the script stops, changes nothing, and points to System Settings → Privacy & Security → Automation. Once it has quit the app, any later stop before the new app opens ends with "Don't Burn Your Brain is not running: start it yourself."
7. Backs up the store before the new app goes in, because the new app may migrate it on its first start. It copies every `DontBurn.store*` and `Local.store*` file of `~/Library/Application Support/<bundle identifier>/`, the `-wal` and `-shm` files included, into a new folder beside it: `~/Library/Application Support/<bundle identifier>.backup-YYYY-MM-DD-HHMMSS`, such as `io.github.slavo775.dontburn.backup-2026-12-01-093000`. It only copies, and never opens the store. `Hook.socket`, `Sessions.json` and `HookInstalls/` are not copied. Without a store file it says "No store to back up yet" and goes on. If a folder of that name exists already, or a copy fails, it stops before anything is installed and removes only the unfinished folder it made. It never removes a backup: the maintainer deletes old ones himself.
8. Swaps the app safely: the new app is copied to `/Applications/.DontBurn.app.new`, the old one is moved to `.DontBurn.app.old`, and the new one is moved into place. If that move fails, the old app is moved back. Then `.old` is removed, with only a warning if that fails.
9. Opens the app and prints its name, version and build, and where the backup is.

**From phase 8:**

- The Release build is signed with Developer ID, notarized and published on GitHub Releases. A version tag starts a GitHub Actions workflow, which costs nothing on a public repository.
- The app updates itself with Sparkle.
- A beta channel in Sparkle gets builds before the stable one.

## On the iPhone (from phase 6)

- **Dev** runs from Xcode on the phone, under the `.dev` identifier. With a free account the build stops working after 7 days, with the paid program after a year.
- **Release** goes through TestFlight. The maintainer installs it as his daily app, and others join through a public link. Every TestFlight build expires after 90 days, so a release goes out at least once a quarter.
- Dev and Release sit side by side on the phone, as on the Mac.

## iCloud

- One container for Mac and iPhone. Dev and Release are kept apart by CloudKit's two environments: Dev builds use Development, Release and TestFlight builds use Production.
- Dev data on the Mac syncs with Dev on the phone, and real data with real data. The two never meet.
- **Before a release whose data model changed,** the schema is deployed to Production in the CloudKit Console. Production only accepts additions: a field or a model can never be renamed or removed there. The maintainer does this deployment himself.

## How a version is released

The Release master runs it after the maintainer says "release vX.Y.Z":

1. The phase's exit line in `docs/spec/plan.md` is met, or the fix is merged.
2. `main` is clean and `./scripts/check` passes on its head.
3. A `CHANGELOG.md` section for the version, from the commits since the last tag, written for people, in a pull request.
4. From phase 6: if any merged card was marked "schema change", the maintainer confirms the CloudKit schema is deployed to Production.
5. An annotated tag `vX.Y.Z` on the merged commit, pushed.
6. A pull request that moves `MARKETING_VERSION` on `main` to the next version.
7. The maintainer installs it: `./scripts/install-release` until phase 8, which backs up the store first ([On the Mac](#on-the-mac)), then the release workflow and TestFlight.
8. A comment on each card of the version with the version number.

## Rules for agents

They are in [../../rules/releases.md](../../rules/releases.md). That file is the only copy.
