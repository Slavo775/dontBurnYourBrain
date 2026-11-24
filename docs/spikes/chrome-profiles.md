# Spike: a Chrome profile for each workspace, and its window brought forward

Card #56, phase 3. Whether a workspace can name one of Google Chrome's profiles, and whether the app can bring that profile's window forward or open a new one, with which permission, and at what cost to privacy. Other browsers were out of scope, apart from one reasoned paragraph.

Tested on macOS 27.2.1 with Google Chrome 157.0.8103.79, on 2026-11-23, with every command sent from a script started in Terminal. The ways to try were listed and committed before anything ran (`991261f`). Every way ran first against a throwaway Chrome: Chrome started with its own user data folder in the temporary folder, holding three throwaway profiles named Acme, Globex and Personal. Only two commands, each run once after the owner's yes, touched his real Chrome. The spike's code, the single steps to repeat it and the full results are in [Spikes/chrome-profiles/README.md](../../Spikes/chrome-profiles/README.md).

## How sure each result is

Every result below is one of four kinds:

- **measured**: the Developer ran it and counted it, on the throwaway Chrome, or once on the owner's Chrome where that is said.
- **repeated**: the Tester ran it again from the README's written steps alone, each round on a fresh scratch folder with fresh Acme, Globex and Personal profiles, and got the same result.
- **reasoned**: it follows from a manual, from Chromium's source, or from macOS's string tables and log. Nobody saw it happen.
- **not tried**: neither.

## The answers

1. **Can the app list Chrome's profiles with their names, reading nothing else?** **Only with macOS's "App Data" permission for Google Chrome.** The names are in Chrome's `Local State` file under `profile.info_cache.<folder>.name`, and decoding only that key worked on the throwaway file (measured, repeated). But macOS 27.2 protects Chrome's own folder as Chrome's private data: the one read of the owner's real file from Terminal was denied, with no prompt (measured once). Whether macOS shows this app the prompt for it was not tried.
2. **Can it bring a profile's existing window forward?** **Not a window the user opened.** Nothing the card allows tells which profile a window belongs to (measured). With Apple events, the app can bring back a window whose id it noted when it opened it: 10 of 10 (measured, repeated).
   **Can it open a new window in a profile?** **Yes.** `open -n -b com.google.Chrome --args --profile-directory=<folder>` opened exactly one new window, in the intended profile and in front, every time: 10 of 10 with the throwaway Chrome not running, 10 of 10 with it running, and 20 of 20 more in the set-ups (measured, repeated). Once on the owner's real Chrome, in 0.67 s (measured). It never brings an existing window forward.
3. **Which permission each way needs.** Opening with `open -n`: none (measured). Reading `Local State` in Chrome's folder: App Data for Google Chrome (measured). Apple events: Automation (measured, but the prompt did not show, because Terminal already had it). Starting Chrome's binary directly: none for the call, but macOS then charges the caller for Chrome's own requests, which brought a Local Network prompt for Terminal (measured).
4. **What can it know about a profile's windows?** **Nothing per profile** (measured, repeated). Without any permission, the window server gives the number of Chrome's on-screen windows, their order and their bounds, for all profiles together. Automation adds each window's id and whether it is minimized or incognito, but it also lets the app read every tab's URL and title and run JavaScript in any page of any profile.

**Recommendation: build the smaller form, with the App Data permission.** The owner decides. See [Recommendation](#recommendation).

## How a try was counted

After each command the helper read three signals every 0.1 s, for up to 5 s, until they agreed, and once more 2 s after the command to catch a late window:

1. **The frontmost app**, from LaunchServices (`lsappinfo front`), by process ID.
2. **Chrome's front window**: the throwaway process's first on-screen normal window, at least 300 by 200 points, in the window server's front-to-back list.
3. **New windows**: on-screen normal windows of the throwaway process that were not there before. Only on-screen windows count, because Chrome keeps hidden windows of its own.

A try was **forward** when the profile's existing window was Chrome's front window, Chrome was the frontmost app, and no new window appeared. It was an **open** when exactly one new window appeared, and whether that window came to the front was recorded on its own. A try was **discarded** when, at the last reading, the app in front was neither the throwaway Chrome nor the terminal the run came from. No window name was read. Which profile a new window belongs to is known only by construction, from the command that opened it.

## Measured runs

Ten tries per run, through Acme, Globex and Personal in turn. Each try started the throwaway Chrome and stopped it again by its process ID.

| Run | Developer, measured | Tester, repeated |
|---|---|---|
| Not running, `open -n` | **10 of 10** one new window, in front. Command until the first window 0.90 to 0.96 s. Settled median 1.12 s, worst 1.14 s | Round 1: **10 of 10**. 0.82 to 0.90 s, median 1.02 s, worst 1.05 s. Rounds 2 and 3: 1 of 1 each, settled 1.09 s and 1.19 s |
| Not running, Chrome's binary | **9 of 9** counted. Try 1 discarded: its window was in front at 0.75 s, then the Local Network prompt came to the front. 0.53 to 0.58 s. Median 0.70 s, worst 0.75 s | Not repeated, because of the Local Network prompt |
| Running, `open -n`, a window of the profile already open | **10 of 10** a new window, in front. **0 of 10** brought the existing window forward. Set-ups 20 of 20. `open` returns in 0.11 s. Median 0.58 s, worst 0.59 s | Round 1: the same counts, set-ups 20 of 20. 0.10 to 0.11 s, median 0.54 s, worst 0.57 s |
| Running, Chrome's binary, a window of the profile already open | **10 of 10** a new window, **0 of 10** forward. Set-ups 20 of 20. The handing-over process ends in 0.21 to 0.22 s. Median 0.40 s, worst 0.41 s | Not repeated |
| A window the app opened, brought forward by Apple events | **10 of 10** forward, no new window. Set-ups 20 of 20. Both events 0.26 to 0.29 s. Median 0.46 s, worst 0.46 s | Round 1: **10 of 10** counted, set-ups 28 of 28, 0.24 to 0.27 s, median 0.43 s, worst 0.43 s. 4 tries discarded: System Settings came to the front after the window had already come forward, most likely the owner. Round 2: 3 of 3, set-ups 6 of 6 |
| The first Apple event | Terminal already held Automation for Google Chrome, so no prompt. It counted 1 window | Rounds 2 and 3: the same, no prompt |
| A profile folder that does not exist (`Profile 9`), not running, `open -n`, 1 try | Chrome **created a new profile** with its default name and opened one window in it | Round 1 with a command the Tester wrote, round 2 from the README's written step: the same |
| The names in the throwaway `Local State` | `3 profiles, 3 with a name`, before Chrome ever ran (206 bytes) and after 54 starts (5,766 bytes). The fourth profile showed up the same way | Every round: `3 profiles, 3 with a name`. Round 1: still read after 35 starts (5,697 bytes), then `4 profiles, 4 with a name` |

"Command" is the time the command took. "Settled" runs from the command to the first reading at which the signals agreed.

- The Developer started 54 throwaway instances and 136 throwaway windows: 52 and 134 in the runs above, plus one early try before the helper counted only on-screen windows and one start by hand to list the windows. The Tester started 35 instances and 83 windows in round 1, six instances in round 2 and four in round 3. Every instance was stopped by its process ID and checked gone.
- In the Apple-event run, right after `set index … to 1` and before `activate`, the terminal was still the frontmost app every time, in both the Developer's and the Tester's runs. Setting the index alone does not bring Chrome forward.

## Part 1: the profile names

- **Where they are.** `Local State`, a JSON file at the top of Chrome's user data folder, holds every profile's name under `profile.info_cache.<folder>.name`. The folder is `Default`, `Profile 1` and so on. The spike's reader decodes that one key and nothing else, because the same `info_cache` also holds account emails and Google account names. Measured, repeated.
- **No permission for a copy outside Chrome's folder.** The throwaway file in the temporary folder needed none. Measured.
- **Chrome's own folder is protected.** With the owner's yes, one read of `~/Library/Application Support/Google/Chrome/Local State` from Terminal failed. The system log shows that `sandboxd` checked the App Data service (`kTCCServiceSystemPolicyAppDataDetailed`) for `com.google.Chrome`, with Terminal as the responsible app, and that it was denied 12 ms later, so no prompt was on screen. The file's size could be read, its content could not. Measured once. The owner took the denial as the result, so it was not run again with a permission.
- **Whether this app gets the prompt** was not tried. Terminal is one of Apple's own apps, and macOS's log says it does not prompt for those in another request. So this app may get the prompt where Terminal got none, or be denied the same way. The feature card has to find out first. Reasoned.
- **The format can change.** `Local State` is not a documented interface, and only Chrome 157 was tried. A later Chrome may move the key, and the app then finds no profiles. Chrome Beta, Canary and Chromium keep their own folders next to Chrome's. Reasoned.

## Part 2: bringing a window forward, or opening one

- **`--profile-directory` always opens a new window.** With the instance running, it never brought the profile's existing window forward: 30 of 30 new windows for `open -n` in the running run, set-ups included, 22 of 22 more in the set-ups of the Apple-event run and the first Apple event, and 30 of 30 for the binary. With the instance not running, it started Chrome with exactly one window in that profile, in front: 10 of 10 for `open -n` and 9 of 9 for the binary. Measured, and repeated for `open -n`.
- **Without `-n`**, LaunchServices drops the arguments while Chrome runs. Not tried on purpose, because it would reach the owner's Chrome. Reasoned from `open`'s manual.
- **Chrome's AppleScript dictionary names no profile.** `sdef` shows windows with properties such as `id`, `index`, `bounds`, `mode` (normal or incognito), `minimized`, `visible`, `given name`, the title and the active tab, and tabs with their title and URL. No class, property or command names a profile, an account or a user. Measured. `make new window` opens in the profile of the last active window, so the app cannot choose the profile that way. Reasoned from Chromium's source.
- **A known window comes forward by its id.** `set index of window id <id> to 1`, then `activate`, both sent to Chrome's process ID: 10 of 10, in a median 0.46 s (measured, repeated). The id is Chrome's own window id, not the window server's number. The two match by bounds. So the app can bring back a window it opened, if it notes the new id after its open command. It cannot find a window the user opened. Whether a window keeps its id when Chrome restarts and restores it was not tried.
- **Chrome not running at all.** Measured only as "the throwaway instance is not running", because the owner's Chrome is never quit. For the real case, reasoned: the same command starts Chrome with that profile only. A profile set to continue where it left off would restore its last windows instead of opening one. Not tried.
- **A folder that does not exist creates a profile.** `--profile-directory=Profile 9`, a folder that `Local State` did not list, made Chrome create a `Profile 9` folder and an `info_cache` entry with Chrome's default name, "Your Chrome" in the system's language, and open a window in it. No question was asked. Measured, repeated.

## Part 3: permissions, and the prompts macOS showed

| Way | Permission | How sure |
|---|---|---|
| Reading `Local State` | None for a copy in the temporary folder. In Chrome's own folder, App Data for Google Chrome. Terminal was denied without a prompt | Measured |
| `open -n -b com.google.Chrome --args …` | None. Chrome runs as its own responsible process | Measured: no prompt in 44 starts and 52 hand-overs to a running instance on the throwaway, and in the one run on the owner's Chrome |
| Chrome's binary, started by the caller | None for the call. But Chrome then runs as the caller's child, and macOS holds the caller responsible for Chrome's own requests | Measured: a Local Network prompt for Terminal |
| Apple events to Chrome | Automation, per sending app and per Chrome's bundle id. One answer covers every Chrome instance, the owner's included | Measured that Terminal already had it. The prompt itself did not show |
| The window server's list, without window names | None | Measured |

**The one prompt macOS showed: Local Network.** It came once, during try 1 of the not-running binary run: "Allow “Terminal” to find devices on local networks?", with "This will allow the app to discover, connect to, and collect data from devices on your networks." Chrome, started as Terminal's child, looked for devices on the network, and macOS asked on Terminal's behalf. The owner answered it himself, before the Tester's first run. No prompt showed in any of the Tester's runs.

Two prompts the ways need did not show. The Mac's interface is not in English, and no prompt's text could be read from the screen without Accessibility or Screen Recording, so these texts come from macOS's string tables, with the app's name filled in. Reasoned.

- **App Data:** "Allow “<app>” to access your “Google Chrome” data?", with "This will allow the app to access your data associated with “Google Chrome” on this Mac." When access is blocked, macOS may post "Data Access Blocked": "“<app>” tried to access your data from other apps and was blocked. You can manage this at any time in Files & Folders settings." The log shows no such notification for Terminal's denied read.
- **Automation:** "“<app>” wants access to control “Google Chrome”. Allowing control will provide access to documents and data in “Google Chrome”, and to perform actions within that app." Under the hardened runtime, the app also needs the `com.apple.security.automation.apple-events` entitlement and an `NSAppleEventsUsageDescription`, or macOS does not ask at all. Reasoned from macOS's log for other apps.

**No Keychain prompt.** Every throwaway launch carried `--use-mock-keychain`, which is meant to keep Chrome away from its "Chrome Safe Storage" item. That the flag worked is reasoned from Chromium's switch, not proven.

## Part 4: what the app can know about a profile's windows

**Nothing per profile.** Three windows, one per throwaway profile, read through every allowed property, differ only in `id`, `index` and `bounds`. Their bounds equal the window server's. Measured, repeated in rounds 2 and 3.

- **With Automation:** how many windows Chrome has in all profiles together, and each window's id, order, bounds, and whether it is minimized, visible or incognito. The cost is high: the same permission lets the app read every tab's URL and title and run JavaScript in any page of any profile, and macOS's prompt says so. The app would hold that power even if it read only window ids. `given name` is text the user typed, so the app should not read it either.
- **Without any permission:** the window server gives the number of Chrome's on-screen windows, their order and bounds, for all profiles together, because every profile's windows belong to one process. Not their titles, which need Screen Recording.
- **How many windows one profile has:** not possible with any way the card allows.

## The owner's real Chrome

The owner said yes to two commands, each run once from Terminal. Nothing else touched his Chrome or its folder, and no Apple event was sent to it.

1. **List the profiles** with the spike's reader. The read was denied, as Part 1 says, and nothing was read. Measured.
2. **Open one window in `Default`**, with `open -n -b com.google.Chrome --args --profile-directory=Default`. Step 1 could not list `Default`, so the owner confirmed himself that one of his profiles uses that folder. With Terminal in front and his Chrome running, the command took 0.15 s. At 0.67 s his Chrome was the frontmost app, with exactly one new window in front. The owner confirmed it opened in the profile whose Profile Path ends in `/Default`. Measured.

In the same second one display switched desktops, so one of his earlier windows went out of view. The owner confirmed that it did not close. He closed the new window himself.

## Recommendation

**Build the smaller form, with the App Data permission.** The owner decides.

A workspace can be linked to one Chrome profile, picked from the list the app reads from `Local State`, and then offers "Open a window in <profile>". Before every open, the app reads `Local State` again and checks that the linked folder is still listed. Then it runs `open -n -b com.google.Chrome --args --profile-directory=<folder>`, or the same through `NSWorkspace.openApplication(at:configuration:)` with `createsNewApplicationInstance`, which is the API behind `open -n` (reasoned).

- **Opening needs no permission and sends no Apple event.** 20 of 20 on the throwaway, settling in a median 1.12 s with Chrome not running and 0.58 s with it running, and once on the owner's Chrome in 0.67 s.
- **Listing and checking need App Data for Google Chrome.** Whether macOS shows this app that prompt was not tried. The feature card finds that out first.
- **Without the permission, the Chrome part is left out.** No profile list, no link and no "Open a window" button, and nothing else changes or nags, as rule 7 of [CLAUDE.md](../../CLAUDE.md) asks. The same when the permission is taken back later, on a Mac without Chrome, and for a workspace without a linked profile. The app never opens a folder it could not confirm.
- **A linked folder that is gone is not opened.** Chrome would create a new profile, so the app says the profile is gone instead.
- **Every open is a new window.** The button says "Open a window", never "Bring forward", and ten clicks are ten windows.
- **Building it as drawn**, with the profile's existing window brought forward, is not possible for windows the user opened. Automation could bring back only windows the app opened itself, and it would let the app read every tab's URL and title in every profile. Bringing forward the user's own window would need Accessibility or Screen Recording, which the spec rules out, or a companion extension in every profile (see below). So the smaller form leaves it out.

The owner's other choices:

- **A typed folder name, without App Data.** The user types the last part of the Profile Path from `chrome://version`, as the owner did for his real Chrome, and the app opens it without reading `Local State`. The app cannot check the name. A typo, or a profile deleted since, makes Chrome create a profile the user never asked for and open a window in it, as `Profile 9` showed. The owner weighs that against rule 10 of [CLAUDE.md](../../CLAUDE.md), "The app only asks".
- **Drop it**, if the app should neither ask for Chrome's data nor take a typed name.

## Other browsers

Reasoned, nothing tried. **Safari** keeps its profiles in its protected container, has no command-line switch for a profile, and its dictionary names no profile, so neither listing nor opening carries over. **Arc** is built on Chromium but organises work in spaces, and its dictionary is said to reach a space by name, which would bring the right space forward. That needs Automation, and Arc is no longer actively developed. **Firefox** lists its profiles in a plain `profiles.ini` and opens one with `-P <name>`, and every running profile is a process of its own. So the app could tell a profile's windows apart by process ID, and might bring them forward with no permission at all, which Chrome does not allow. It is the browser where the idea carries furthest.

## Ideas not tried, and their cost

- **Naming the app's own windows.** `given name` can be set by Apple events and shows as the window's title. The app could tag the window it opened with the workspace's name and find it again after a restart. It changes what the user sees in Chrome, and needs Automation.
- **A companion extension in every profile**, talking to the app through native messaging. The only way found that could list and bring forward a profile's own windows, the user's included, without Accessibility. It needs an extension installed in every profile and a manifest written into Chrome's folder, which is changing another tool's settings.
- **Ruled out before anything ran:** Chrome's Profiles menu (Accessibility), window titles (Screen Recording, and window names are off limits), remote debugging (its target list carries every page's URL and title, and recent Chrome refuses it on the default user data folder), each profile's own `Preferences` file (it means reading inside a profile folder), other keys of `Local State`, and `--profile-email` (the app would have to know the email).

## What was not tried

- Whether macOS shows this app the App Data prompt, and the app's behaviour once it is given or denied.
- The Automation prompt itself: Terminal already had it.
- Everything from the menu bar app or from a signed, hardened build. Every command came from a script in Terminal.
- Chrome not running at all, and a profile set to continue where it left off.
- A new window when Chrome's window is on another desktop or minimized. The new window appeared on the current desktop.
- Whether a window keeps its id across a Chrome restart.
- `open -b` without `-n`, on purpose, and `NSWorkspace.openApplication`, reasoned to be the same as `open -n`.
- Any Chrome other than 157, and Chrome Beta, Canary or Chromium.
- The Tester never repeated the binary runs, because of the Local Network prompt.
- Other browsers.

## For the feature card

- Find out first whether macOS shows this app the App Data prompt for Google Chrome. The recommended form rests on it.
- Read only `profile.info_cache.<folder>.name` from `Local State`, and read it again before every open.
- Open with `open -n -b com.google.Chrome --args --profile-directory=<folder>`, or `NSWorkspace.openApplication` with `createsNewApplicationInstance`. **Never start Chrome's binary as the app's child**: macOS would then charge the app for Chrome's permissions, such as Local Network.
- `open -n` starts a second Chrome process for a moment, which hands its arguments to the running one and ends.
- Never open a folder the app could not confirm, because Chrome creates a profile for it.
- Say "Open a window in <profile>". Every open is a new window.
- Leave the Chrome part out without the permission, without Chrome, and for a workspace with no linked profile. The Tester checks each case.

## What this changes in the spec

- [docs/spec/plan.md](../spec/plan.md), phase 3, "A spike: whether a workspace can name a Chrome profile and bring its window forward." **Answered.** It can open a window in a profile, not bring the user's own window forward, and listing the profiles needs App Data. The line now points here.
- Nothing else in the spec names Chrome yet. Its rows in features, design and feasibility come with the owner's choice and the feature card written from this note.
