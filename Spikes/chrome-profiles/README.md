# Spike: a Chrome profile for each workspace, and its window brought forward

Card #56. Throwaway code that answers four questions about Google Chrome on macOS:

1. Can the app list Chrome's profiles with the name the user gave each, without reading anything else in Chrome's folder?
2. Can it bring an existing window of one profile to the front? If not, can it open a new window in that profile?
3. Which macOS permission does each way need?
4. What can it know about a profile's windows, such as how many are open, and at what cost to privacy?

It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

## The ways, written before anything ran

Each way is tried first against a throwaway Chrome instance: Chrome started with its own user data folder in `$TMPDIR`, holding three throwaway profiles named Acme, Globex and Personal. A second Chrome with its own user data folder is a separate process with its own single instance, so the owner's Chrome and its profiles are not touched. Only the last stage, after the owner's yes, touches his real Chrome.

| # | Way | What it needs | What it might answer |
|---|---|---|---|
| 1 | Read Chrome's `Local State` file, a JSON file at the top of the user data folder, and take only `profile.info_cache.<directory>.name` | One file read in Chrome's folder. For the owner's real file, his yes. No permission prompt expected: Chrome is not sandboxed and its folder is not one macOS protects | Part 1: every profile's name and its directory (`Default`, `Profile 1`, …), without starting Chrome. Nothing about windows. The file's `info_cache` also holds account emails and Google account names, so the code decodes the one key and nothing else |
| 2 | `open -n -b com.google.Chrome --args --user-data-dir=<folder> --profile-directory=<directory>` | Starts a process through LaunchServices. No permission expected. When an instance for that user data folder already runs, the new process hands its arguments to it and exits | Part 2: whether it brings an existing window of the profile forward or opens a new one, with the instance running and not running, and whether the window comes to the front |
| 3 | The binary inside the app bundle, `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`, with the same arguments | Starts a process as a child of the caller, without LaunchServices. No permission expected, though macOS may hold the caller responsible for Chrome's own requests while Chrome is its child | The same as 2, and whether a window comes forward without the activation LaunchServices grants |
| 4 | `open -b com.google.Chrome --args …` without `-n` | Nothing new | **Not tried, on purpose.** While any Chrome runs, LaunchServices activates the running instance and drops the arguments. With the owner's Chrome running, that instance may be his |
| 5 | Chrome's AppleScript dictionary, read statically: `sdef "/Applications/Google Chrome.app"` | Reads the app bundle. No Apple event, no prompt | Which classes and properties exist for windows, and whether anything in the dictionary names a profile. Done before any live Apple event |
| 6 | Live Apple events to the throwaway instance, addressed by its process ID with Scripting Bridge (`SBApplication(processIdentifier:)`): count the windows, read window `id`, `index`, `given name`, `mode`, `minimized`, `visible` and `bounds`, set a window's `index` to 1, and `activate` | Automation: macOS asks once whether the sending app (the terminal the spike runs in) may control Google Chrome. The answer is stored per sending app and per target bundle ID, so it covers the owner's Chrome as well, which has the same bundle ID | Part 2: whether a window can be brought forward by its `id`, and whether any property tells one profile's window from another's. Part 4: how many windows are open. Never a window's `name`, a tab's `title` or `URL`, and never `execute javascript` |
| 7 | The window server's list, `CGWindowListCopyWindowInfo`, filtered to the throwaway process ID, without `kCGWindowName` | Nothing. The name would need Screen Recording, which is ruled out | Part 4: how many windows the process has and which is in front. Not which profile a window belongs to: every profile's windows belong to one process |
| 8 | `NSWorkspace.openApplication(at:configuration:)` with `createsNewApplicationInstance` and `arguments` | The same as 2 | Not tried separately: it is the API behind `open -n`, so it should behave as way 2. Reasoned |

Ideas set aside before anything ran, each with its reason:

- **Each profile's own `Preferences` file** holds the profile name too, but reading it means reading inside a profile folder. Way 1 reads one file at the top of the user data folder instead.
- **Other keys of `Local State`**, such as the last used profile or the profiles open at the last exit. They would tell which profiles had windows, but the card allows only the names from this file.
- **Chrome's Profiles menu**, which lists the profiles and brings a profile's window forward, is reachable only through Accessibility, which the spec rules out.
- **Window titles.** Chrome may show the profile name in a window's title, but reading a window's name is ruled out, and the window server shows it only with Screen Recording.
- **Remote debugging** (`--remote-debugging-port`) tells each page's browser context apart, which maps to a profile. Chrome must be started with it, recent Chrome refuses it on the default user data folder, and its target list carries every page's URL and title.
- **A companion Chrome extension** in every profile, talking to the app through native messaging, could list and focus that profile's windows. It needs an extension installed in each profile and a manifest written into Chrome's folder, which is changing another tool's settings. Not tried. Its cost goes into the note.
- **`--profile-email`** picks a profile by its account email. The app would have to know the email.

### What counts as a hit

- **Bringing forward:** the intended profile's existing window is Chrome's front window, the throwaway instance is the frontmost app, and no new window appeared.
- **Opening:** exactly one new window appeared, in the intended profile. Whether it also came to the front is recorded on its own.

### The case "Chrome is not running"

The owner's Chrome is never quit, so this is measured as "the throwaway instance is not running": each user data folder has its own single instance. What it means for the real case, where no Chrome runs at all, is reasoned.
