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
  `open -g .worktrees/<branch>/DerivedData/Build/Products/Debug/DontBurn.app`, then `pgrep -f .worktrees/<branch>/DerivedData/Build/Products/Debug/DontBurn.app`.
- **Stop only the process you started, by the process ID you recorded.** Never `pkill -f`, `killall` or another name pattern.
- **Never make the Dev app frontmost:** no `activate()`, no `open` without `-g`, no `open -a`, and nothing else that does it. Focus elements through the accessibility API, and send keys only with `CGEventPostToPid` to the recorded process ID. The maintainer may be typing. If the keys do not arrive without activating the app, report the item as not checked, never as a pass, and never activate it.
  - The one exception is a control that brings the app forward by design, such as Settings…. Press it only for the check that needs it. As soon as that check is done, close the window it opened with `AXPress` on that window's `AXCloseButton`. Then check that `NSWorkspace.shared.frontmostApplication?.processIdentifier` is not the recorded process ID. If it still is, say so in the report, and never activate another app to fix it. Before the report, check that the fields touched during the step hold only what the check typed, and name the step in the report.
- **The compact panel takes the keys while it is open**, without bringing the app forward, so the maintainer's typing can land in it. Open it only for the check that needs it, **send that check's keys at once, each only after the accessibility API shows the panel's window of the recorded process ID open,** and close it as soon as that check is done: Escape sent with `CGEventPostToPid`, or an `AXPress` on the menu bar item. On the ⌘N custom block form, Escape only goes back to the main page, so send it twice there. Never leave the panel open while you wait, and never reopen it in a loop. **When the menu bar item cannot be reached, as while the screen is locked, send nothing and press nothing: wait, or read what happened from the system log, and look again. On an unlocked screen, an item that is not found is handled as "When the item is hidden" in "Checking a screen" says.** Before the report, check that the timer is in the state your steps put it in. If it is not, **discard that run and** say so in the report: the maintainer's keystrokes may have reached the panel.

## Checking a screen

- Go through every done-when item by hand, and through the case where an optional part is missing.
- **Light and dark are each checked on a fresh launch with the mode already set for that launch.** Never by switching the mode while the app is open, and never by changing the system's appearance. The Dev build takes the mode as a launch argument: `open -g <app> --args -DontBurnAppearance light` or `dark`. It sets the app's appearance (`NSApp.appearance`). The menu bar item and the menu it opens do not follow it: they are drawn in the menu bar's appearance, which follows the system. A screen the argument does not reach is checked in the system's current mode, and the other mode is reported as not checked, never as a pass.
- Screenshots come from the Dev build with the sample data, saved in `.worktrees/screenshots/<branch>/`, which git ignores. They are never committed. **Each is taken of one window of the recorded process ID, by its window ID: `screencapture -l <id> -o`, with the ID taken from `CGWindowListCopyWindowInfo` where `kCGWindowOwnerPID` is the recorded process ID. Never a region (`-R`), the whole screen, or an interactive capture. These record whatever lies at that place, the owner's windows included. A capture that shows anything but the app is deleted at once by its literal path and reported.** The verdict lists their paths, and the Leader shows them to the owner before Ready to merge.
- **A screen test proves that the screen reacts.** It performs at least one real interaction, such as a click, typed text or a shortcut, and checks what changed.
- **Interaction goes through the accessibility API**, on elements owned by the process ID you recorded, with `AXPress`. A mouse event is sent only after `AXUIElementCopyElementAtPosition` on `AXUIElementCreateSystemWide()`, at that exact point, returns an element whose `AXUIElementGetPid` is the recorded process ID. An error counts as not ours. The cursor is never moved, and nothing else is clicked. The maintainer's mouse is live, and a click aimed at coordinates lands in whatever app is there.
- **Reaching the menu bar item:**
  1. Find `MenuBarAgent`'s process ID with `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")`, and make its element with `AXUIElementCreateApplication`.
  2. Read its `AXWindows`: one window per display's menu bar. Go down `AXChildren` (one `AXGroup` per item, then the item). The app's item is the `AXButton` whose `AXUIElementGetPid` is the recorded process ID. Its `AXTitle` is the shown text. The app's entries on other displays are not `AXButton`s and are skipped. Search exactly these three levels, window → group → item, and never deeper: a deeper search reaches the app's own controls and presses them.
  3. The button offers two actions. `AXPress` opens or closes the compact panel, and the panel rule in "Running the Dev build" applies. Show menu opens the right-click menu, as the next point says. Its name in `AXUIElementCopyActionNames` starts with `Name:Show menu`, and the rest of it changes with every launch, so match that prefix and pass the whole name to `AXUIElementPerformAction`. `AXCustomActions` reads nil on this element, so never look for it there.
- **The right-click menu is opened with Show menu**, never with a mouse event to the item. While it is open it takes the keys of the whole Mac, as the panel does, so the maintainer's typing can pick one of its items. Open it only for the check that needs it, and never while the screen is locked:
  1. Before you perform Show menu, register an `AXObserver` for `kAXMenuOpenedNotification` on `AXUIElementCreateApplication` of the recorded process ID. No `AXChildren` list holds the menu, so the notification is how it is found. Never look for it in the app's `AXMenuBar`, where the app's main menu also shows as an `AXMenu`.
  2. Perform Show menu once. It returns at once, and it closes the panel if the panel is open. Take the `AXMenu` from the notification, and check that its `AXUIElementGetPid` is the recorded process ID. If no menu arrives within a second, send Escape with `CGEventPostToPid` only when `CGWindowListCopyWindowInfo` shows a new window of the recorded process ID at layer 101, then report the menu as not checked.
  3. Do that check's steps at once. The items are the menu's `AXChildren`, each an `AXMenuItem`, pressed with `AXPress`. Quit is the item whose `AXTitle` starts with `Quit `.
  4. Close the menu as soon as that check is done: `AXCancel` on the `AXMenu`, or Escape sent with `CGEventPostToPid`. Then check with `CGWindowListCopyWindowInfo` that no window of the recorded process ID at layer 101 is left. Never leave the menu open while you wait, and never perform Show menu again while it is open.
  5. Before the report, check that the timer is in the state your steps put it in. If it is not, discard that run and say so in the report: the maintainer's keystrokes may have reached the menu.
- **Stopping the app.** `AXPress` on Quit in the menu stops it. When the menu cannot be used, stop it with `kill <pid>` on the recorded process ID. Either way, check with `ps -p <pid>` that the process is gone.
- **When the item is hidden**, for example behind the menu bar's overflow chevron on a notched display, no such button is found. Never click the chevron. Stop the recorded process ID, and report the item as not checked, never as a pass. To check it after all, the Leader asks the owner to make the item visible, and the check runs again.

## Spikes

The Tester repeats the result the spike reports and confirms its numbers. Nothing else.
