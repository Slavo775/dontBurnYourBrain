# Releases, versions and build variants

How the app is versioned, how a development build and the maintainer's daily copy live side by side on one Mac and one iPhone, and what agents may and may not do with either.

## Versions

- **One place.** `MARKETING_VERSION` in `project.yml` is the version for humans, such as `0.3.0`. Nothing in the code repeats it. The app reads it from its bundle, and the hook tool gets it baked in at build time.
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
- **The app says what is running.** Settings, General shows version, build and variant. The Dev build also shows the short commit hash.
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
| Global shortcuts, launch at login | Off by default | On, as set by the user | On, as set by the user |
| Gets updates from | Xcode | `./scripts/install-release`, later Sparkle | Sparkle's beta channel |

Because the identifiers differ, macOS treats Dev and Release as two separate apps: separate data folders, settings, Keychain items, permissions and notifications. Both can sit in the menu bar at the same time. The Dev build has a tinted icon and shows "DEV" in its menu bar item, so the two are never confused.

### Everything with a name outside the app follows the bundle identifier

So that Dev and Release never answer each other's messages:

- the data folder (already in `StoreLocation`)
- the channel the hook tool talks to
- the URL scheme: `dontburn://` for Release, `dontburn-dev://` for Dev
- Keychain service names, defaults suites and the logging subsystem
- notification names and anything registered with launchd

The hook tool sends to Release by default. `--target dev` or `DONTBURN_TARGET=dev` sends to Dev. Hooks installed in the maintainer's real Claude Code profiles therefore always reach his daily copy. Dev is tested from a scratch project.

## On the Mac

**Until phase 8, without a paid Apple developer account:**

- `./scripts/install-release` builds the Release variant from a clean `main` and quits the running Release app politely, by its bundle identifier. It then replaces the app in `/Applications` and starts it again.
- It signs with the maintainer's Personal Team when `Local.xcconfig` names one, and to run locally otherwise. With the local signature macOS may forget permissions after an update. The Personal Team avoids that.
- The maintainer runs it when a version is tagged, or when he wants to try `main` in his daily copy.

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
7. The maintainer installs it: `./scripts/install-release` until phase 8, then the release workflow and TestFlight.
8. A comment on each card of the version with the version number.

## Rules for agents

These are binding, like everything in `rules/`.

1. **Build, run and test only the Dev variant.** Never start, stop, replace or read the data of the installed Release app, and never run `./scripts/install-release`, unless the maintainer asks for it in this session.
2. **Never change the version or the build number, and never create or move a tag.** Only the Release master does that, during a release, after the maintainer's yes.
3. **Never hard-code the version, the bundle identifier or the app's name in code.** Read them from the bundle. Values that differ between variants come from build settings.
4. **Anything named outside the app is derived from the bundle identifier** (see the list above). The Reviewer checks this on every pull request that adds one.
5. **Dev registers no global shortcut and no login item by default.**
6. **Hooks:** never point a real profile's hook at Dev. Dev is tested from a scratch project with `--target dev`.
7. **iCloud:** Dev builds use the Development environment only. Deploying the schema to Production is the maintainer's job.
8. **A card that changes the data model** gets the comment "schema change", so the release remembers step 4.
9. **Screenshots** come from Dev with the sample data.
