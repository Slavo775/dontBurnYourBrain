#!/bin/bash
# Opens one spike window with two tabs, titled "dontburn-spike <App> A" and
# "dontburn-spike <App> B", in Terminal or iTerm2. Each tab runs start-tab.sh,
# which writes the handle a hook in that tab would see to <folder>/<app>-A and
# <folder>/<app>-B. Then the handles are checked against the terminal's own
# AppleScript. Never types into a tab.
# Usage: open-tabs.sh terminal|iterm2 <folder>
set -euo pipefail
usage="usage: open-tabs.sh terminal|iterm2 <folder>"
app=${1:?$usage}
dir=${2:?$usage}
case "$dir" in
*[!A-Za-z0-9._/-]*)
    echo "The folder path may hold only letters, digits and . _ / -" >&2
    exit 2
    ;;
esac
cp "$(dirname "$0")/start-tab.sh" "$dir/start-tab.sh"
a="$dir/$app-A" b="$dir/$app-B"
rm -f "$a" "$b"

case "$app" in
terminal)
    # Terminal 2.15 can open a tab by script: "do script in new tab … next to".
    osascript - "$dir" "$a" "$b" >/dev/null <<'EOF'
on run argv
	set {d, a, b} to argv
	tell application "Terminal"
		set tabA to do script "/bin/bash " & d & "/start-tab.sh " & a & " Terminal A"
		set tabB to do script in new tab "/bin/bash " & d & "/start-tab.sh " & b & " Terminal B" next to tabA
		set custom title of tabA to "dontburn-spike Terminal A"
		set custom title of tabB to "dontburn-spike Terminal B"
	end tell
end run
EOF
    ;;
iterm2)
    osascript - "$dir" "$a" "$b" >/dev/null <<'EOF'
on run argv
	set {d, a, b} to argv
	tell application "iTerm2"
		set w to create window with default profile command "/bin/bash " & d & "/start-tab.sh " & a & " iTerm2 A"
		tell w to create tab with default profile command "/bin/bash " & d & "/start-tab.sh " & b & " iTerm2 B"
	end tell
end run
EOF
    ;;
*)
    echo "$usage" >&2
    exit 2
    ;;
esac

for _ in $(seq 50); do
    [ -s "$a" ] && [ -s "$b" ] && break
    sleep 0.1
done

for f in "$a" "$b"; do
    tty=$(sed -n 's/^tty=//p' "$f")
    iterm=$(sed -n 's/^iterm=//p' "$f")
    if [ "$app" = terminal ]; then
        seen=$(osascript -e "tell application \"Terminal\" to get tty of tabs of windows" | tr -d ' ' | tr ',' '\n' | grep -cx "$tty" || true)
        echo "$(basename "$f"): tty $tty, held by $seen Terminal tab(s) by AppleScript"
    else
        uuid=${iterm#*:}
        seen=$(osascript -e "tell application \"iTerm2\" to get tty of sessions of tabs of windows whose unique ID is \"$uuid\"" 2>/dev/null | tr -d ", " || true)
        echo "$(basename "$f"): ITERM_SESSION_ID w…:$uuid, tty $tty. AppleScript's tty for that unique ID: $seen"
    fi
done
