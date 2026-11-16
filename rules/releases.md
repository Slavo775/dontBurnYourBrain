# Releases and build variants: rules for agents

How versions, the Dev and Release builds and a release work is described in [../docs/process/releases.md](../docs/process/releases.md). These are the rules that follow from it.

1. **Build, run and test only the Dev variant.** Never start, stop, replace or read the data of the installed Release app, and never run `./scripts/install-release`, unless the maintainer asks for it in this session.
2. **Never change the version or the build number, and never create or move a tag.** Only the Release master does that, during a release, after the maintainer's yes.
3. **Never hard-code the version, the bundle identifier or the app's name in code.** Read them from the bundle. Values that differ between variants come from build settings.
4. **Anything named outside the app is derived from the bundle identifier:** the data folder, the channel the hook tool talks to, the URL scheme, Keychain service names, defaults suites, the logging subsystem, notification names and anything registered with launchd. The Reviewer checks this on every pull request that adds one.
5. **Dev registers no global shortcut and no login item by default.**
6. **Hooks:** never point a real profile's hook at Dev. Dev is tested from a scratch project with `--target dev`.
7. **iCloud:** Dev builds use the Development environment only. Deploying the schema to Production is the maintainer's job.
8. **A card that changes the data model** gets the comment "schema change", so the release remembers to deploy the schema.
9. **Screenshots** come from Dev with the sample data.
