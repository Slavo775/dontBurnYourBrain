#!/bin/bash
# Spike for card #7: the guided pass, for one person at the Mac. Run it in Terminal from the
# repository root: Spikes/editor-focus/hand-steps.sh <scratch folder> [first part, default 1]
# It prompts each step, runs editor-check.swift, and appends every line to <scratch>/hand-steps.log.
# Focus jumps between VS Code, Cursor and Terminal the whole time. Keep your hands off the keyboard
# and the mouse whenever it says "hands off".
set -u

scratch=${1:?usage: Spikes/editor-focus/hand-steps.sh <scratch folder> [first part]}
first=${2:-1}
helper="$(dirname "$0")/editor-check.swift"
log="$scratch/hand-steps.log"
[ -d "$scratch/acme-web" ] || { echo "$scratch is not the spike's scratch folder"; exit 2; }

say() { printf '\n%s\n' "$*" | tee -a "$log"; }
check() { echo "> $*" >>"$log"; swift "$helper" "$1" "$scratch" "${@:2}" 2>&1 | tee -a "$log"; }
attempt() { check try "$@"; }
wait_key() { read -r -p "Press Return when done: " _; }
ask() {
    read -r -p "$1 " answer
    echo "owner: $1 $answer" >>"$log"
}
part() { [ "$first" -le "$1" ]; }

say "== Guided pass started $(date '+%Y-%m-%d %H:%M')"

if part 1; then
    say "== Part 1, hands off for about 6 minutes. The spike windows A (acme-web) and B (globex-app)
are opened in both editors when missing, then focused about 100 times."
    wait_key
    for editor in vscode cursor; do
        attempt "$editor" open A
        attempt "$editor" open B
    done
    for editor in vscode cursor; do
        for route in open cli; do
            check measure "$editor" "$route"
        done
        # Activate only: the editor comes forward with its last active window, which is B here.
        attempt "$editor" app A A
    done
fi

if part 2; then
    say "== Part 2, hands off for about 3 minutes. Subfolders, the /var spelling, and a dev container.
Each editor opens new windows here: two subfolder windows, and two for acme-container."
    wait_key
    for editor in vscode cursor; do
        attempt "$editor" open api
        attempt "$editor" cli web
        attempt "$editor" open B-var B
        attempt "$editor" cli B-var B
        attempt "$editor" cli container
        attempt "$editor" open container-path
        attempt "$editor" cli container-path
        attempt "$editor" open container-host
        attempt "$editor" cli container-host
        attempt "$editor" cli container container
    done
    ask "Did a window show a new editor tab named acme-container, and in which editor? (type, then Return)"
fi

if part 3; then
    for editor in vscode cursor; do
        name=$([ "$editor" = vscode ] && echo "VS Code" || echo Cursor)
        before=$(grep -c '"SessionStart"' "$scratch/events.jsonl" 2>/dev/null)
        say "== Part 3, $name. Click the $name window named acme-web (the Window menu lists it). Open its terminal (Terminal, New
Terminal) and type this line, with CLAUDE_CONFIG_DIR=<profile folder> in front if you want a profile:
  CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1 command claude --model haiku --setting-sources project,local --permission-mode default
Answer \"Yes, I trust this folder\" if Claude Code asks. Leave the session running, come back here."
        wait_key
        if [ "$(grep -c '"SessionStart"' "$scratch/events.jsonl" 2>/dev/null)" = "${before:-0}" ]; then
            say "No new SessionStart in the log, so the hook did not run. Skipping $name."
            continue
        fi
        say "Hands off for 20 seconds."
        check session open
        check session cli
        say "Type /exit in that session, then come back here."
        wait_key
    done
fi

if part 4; then
    for editor in vscode cursor; do
        name=$([ "$editor" = vscode ] && echo "VS Code" || echo Cursor)
        for route in open cli; do
            say "== Part 4, minimized. Click the yellow button of the $name window named acme-web, then
come back here. Hands off after Return."
            wait_key
            attempt "$editor" "$route" A A
        done
    done
fi

if part 5; then
    for editor in vscode cursor; do
        name=$([ "$editor" = vscode ] && echo "VS Code" || echo Cursor)
        say "== Part 5, another Space. Open Mission Control (Ctrl-Up). Drag the $name window named
acme-web onto another desktop of its display (add one with + if needed). Click the desktop you
were on, then come back here. Hands off after Return, and watch the screen."
        wait_key
        attempt "$editor" open A A
        ask "Did the screen slide to the other desktop with acme-web in front? (type, then Return)"
        attempt "$editor" cli A A
        ask "And this time? (type, then Return)"
    done
fi

if part 6; then
    for editor in vscode cursor; do
        name=$([ "$editor" = vscode ] && echo "VS Code" || echo Cursor)
        say "== Part 6, $name. Find the $name window named acme-container [Dev Container ...]. Wait until
it has connected. Open its terminal (Terminal, New Terminal) and type: sh probe.sh $editor"
        wait_key
        if [ -f "$scratch/acme-container/probe-$editor.txt" ]; then
            tee -a "$log" <"$scratch/acme-container/probe-$editor.txt"
        else
            say "No probe-$editor.txt. Skipped."
        fi
    done
fi

if part 7; then
    say "== Part 7. Close every window this pass opened, in both editors, with File, Close Window
(Shift-Cmd-W): acme-web, globex-app, api, web, both acme-container windows, and any other window on
one of these folders. Choose \"Don't Save\" if a window asks."
    wait_key
    check windows
fi

say "== Guided pass ended $(date '+%Y-%m-%d %H:%M'). The log is $log"
