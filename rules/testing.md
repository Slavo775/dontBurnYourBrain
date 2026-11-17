# Testing

## Who writes tests

Only the Tester writes and changes tests. The Developer and the Designer run them. When a test fails because behaviour changed on purpose, they leave the test alone and say so in their report. A bug the Tester finds goes back through the Leader. It is never fixed by the Tester and never hidden by a changed test.

## What is worth testing

- Every rule in `DontBurnCore`, at the lowest level that proves it. The target is 80% line coverage there. Views have no target.
- The edges: empty, maximum, invalid, concurrent, and an optional part that is missing.
- Not Apple's code, and not the same rule twice.
- A test's name says the rule it proves.
- Unit tests use Swift Testing (`@Test`, `#expect`). Screen tests are a few smoke tests, because they are slow.

## The clock and the data

- Time is passed in. A test hands over fixed dates. It never sleeps and never reads the system clock.
- Tests use a store in memory, or a temporary folder that is removed afterwards, and only the sample data: Acme, Globex and Personal.
- **Anything that deletes or rewrites data runs against a throwaway store.** Never against the Dev store other work relies on, and never against real data.

## A skipped test is not a pass

Report it as skipped, with the reason. Run tests with the settings the check command uses. The simplest way is `./scripts/check` itself.

## Running the Dev build

For the Tester, and for a Developer or Designer who starts the app.

- Only the Dev variant. See [releases.md](releases.md).
- Start it and record its process ID:
  `open .worktrees/<branch>/DerivedData/Build/Products/Debug/DontBurn.app`, then `pgrep -f .worktrees/<branch>/DerivedData/Build/Products/Debug/DontBurn.app`.
- **Stop only the process you started, by the process ID you recorded.** Never `pkill -f`, `killall` or another name pattern.

## Checking a screen

- Go through every done-when item by hand, and through the case where an optional part is missing.
- **Light and dark are each checked on a fresh launch with the mode already set for that launch.** Never by switching the mode while the app is open, and never by changing the system's appearance. The Dev build takes the mode as a launch argument: `open <app> --args -DontBurnAppearance light` or `dark`. It sets the app's appearance (`NSApp.appearance`). The menu bar item and the menu it opens do not follow it: they are drawn in the menu bar's appearance, which follows the system. A screen the argument does not reach is checked in the system's current mode, and the other mode is reported as not checked, never as a pass.
- Screenshots come from the Dev build with the sample data, taken with `screencapture` and saved in `.worktrees/screenshots/<branch>/`, which git ignores. They are never committed. The verdict lists their paths, and the Leader shows them to the owner before Ready to merge.
- **A screen test proves that the screen reacts.** It performs at least one real interaction, such as a click, typed text or a shortcut, and checks what changed.

## Spikes

The Tester repeats the result the spike reports and confirms its numbers. Nothing else.
