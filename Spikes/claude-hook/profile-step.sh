#!/bin/bash
# Spike for card #5: put the spike's hook into a real profile's settings.json and take it out
# again, so that the file ends byte-identical to its backup. Touches only
# <profile dir>/settings.json and reads nothing else in the profile folder.
#
#   profile-step.sh precheck  <profile dir> <work dir>  stops unless an install can be undone byte for byte
#   profile-step.sh install   <profile dir> <work dir>  runs the precheck, backs up, adds one hook group per event
#   profile-step.sh uninstall <profile dir> <work dir>  removes only those groups, then compares with the backup
#   profile-step.sh selftest                            runs all of it on made-up files in a temporary folder
#
# The hook is <work dir>/spike-hook.sh, so it logs to <work dir>/events.jsonl. When settings.json is
# a symlink, the precheck stops: pass the folder of the file it points to instead.
# Exit codes: 3 the precheck stopped, 4 the file differs from the backup after uninstall,
# 5 refused before writing anything.
set -uo pipefail

events='["SessionStart","UserPromptSubmit","PermissionRequest","Notification","Stop","SubagentStart","SubagentStop","SessionEnd"]'

stop() {
    echo "STOP: $1"
    exit 5
}

# Writes JSON in place, which keeps the inode and the mode, and ends it with a newline only if the
# backup did. Writes nothing unless it was given a JSON object, so a failed jq never empties the file.
put() {
    printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1 || stop "jq gave no JSON object, settings.json is unchanged"
    if [ "$(tail -c1 "$work/settings.json.backup" | od -An -tx1 | tr -d ' ')" = 0a ]; then
        printf '%s\n' "$1" >"$f"
    else
        printf '%s' "$1" >"$f"
    fi
}

selftest() {
    local t fail=0
    t=$(mktemp -d -t dontburn-profile-test)
    mkdir -p "$t/shared" "$t/plain" "$t/emptyhooks" "$t/hand" "$t/link" "$t/changed"
    printf '%s\n' '{' '  "model": "opus",' '  "permissions": {' '    "allow": [' '      "Bash(git status)"' '    ]' '  },' \
        '  "hooks": {' '    "Stop": [' '      {' '        "hooks": [' '          {' '            "type": "command",' \
        '            "command": "~/bin/acme-notify"' '          }' '        ]' '      }' '    ]' '  }' '}' >"$t/shared/settings.json"
    printf '%s' '{
  "theme": "dark",
  "env": {
    "ACME_REGION": "eu"
  }
}' >"$t/plain/settings.json"
    printf '%s\n' '{' '  "hooks": {}' '}' >"$t/emptyhooks/settings.json"
    printf '%s\n' '{' '    "theme": "dark",' '    "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "~/bin/globex-bell" } ] } ] }' '}' \
        >"$t/hand/settings.json"
    ln -s ../shared/settings.json "$t/link/settings.json"
    cp "$t/shared/settings.json" "$t/changed/settings.json"
    mkdir -p "$t/hookslist" "$t/twice" "$t/badhad"
    printf '%s\n' '{' '  "hooks": []' '}' >"$t/hookslist/settings.json"
    cp "$t/shared/settings.json" "$t/twice/settings.json"
    cp "$t/shared/settings.json" "$t/badhad/settings.json"

    # A work folder with a stand-in for the hook.
    workdir() { mkdir -p "$1" && printf '#!/bin/sh\nexit 0\n' >"$1/spike-hook.sh" && chmod +x "$1/spike-hook.sh"; }
    same() { cmp -s "$1" "$2" && echo same; }

    expect() {
        local name=$1 want=$2 pattern=$3 got
        shift 3
        "$@" >"$t/out" 2>&1
        got=$?
        if [ "$got" = "$want" ] && grep -q -- "$pattern" "$t/out"; then
            echo "PASS $name"
        else
            echo "FAIL $name (exit $got, wanted $want and \"$pattern\")"
            sed 's/^/     /' "$t/out"
            fail=1
        fi
    }
    for p in shared plain emptyhooks; do
        workdir "$t/w-$p"
        expect "$p: install adds 8 groups" 0 "installed: 8 groups" "$0" install "$t/$p" "$t/w-$p"
        expect "$p: uninstall leaves it byte-identical" 0 "byte-identical" "$0" uninstall "$t/$p" "$t/w-$p"
    done
    expect "hand-formatted file: precheck stops" 3 "round trip" "$0" precheck "$t/hand" "$t/w-hand"
    expect "symlink: precheck stops" 3 "symlink" "$0" precheck "$t/link" "$t/w-link"
    expect "missing file: precheck stops" 3 "does not exist" "$0" precheck "$t/missing" "$t/w-missing"

    cp "$t/hookslist/settings.json" "$t/hookslist.copy"
    workdir "$t/w-hookslist"
    expect '"hooks": []: install stops at the precheck' 3 "not an object" "$0" install "$t/hookslist" "$t/w-hookslist"
    expect '"hooks": []: the file is unchanged' 0 same same "$t/hookslist/settings.json" "$t/hookslist.copy"

    cp "$t/shared/settings.json" "$t/shared.copy"
    mkdir -p "$t/w-none"
    expect "uninstall without an install: stops" 5 "holds no install" "$0" uninstall "$t/shared" "$t/w-none"
    expect "uninstall without an install: the file is unchanged" 0 same same "$t/shared/settings.json" "$t/shared.copy"
    mkdir -p "$t/w space"
    printf '#!/bin/sh\n' >"$t/w space/spike-hook.sh" && chmod +x "$t/w space/spike-hook.sh"
    expect "work path with a space: install stops" 5 "may hold only" "$0" install "$t/shared" "$t/w space"
    mkdir -p "$t/w-nohook"
    expect "work folder without the hook: install stops" 5 "copy spike-hook.sh" "$0" install "$t/shared" "$t/w-nohook"
    workdir "$t/w-readonly" && chmod a-w "$t/w-readonly"
    expect "backup cannot be written: install stops" 5 "could not back up" "$0" install "$t/shared" "$t/w-readonly"
    chmod u+w "$t/w-readonly"
    expect "refused installs: the file is unchanged" 0 same same "$t/shared/settings.json" "$t/shared.copy"

    workdir "$t/w-twice" && workdir "$t/w-twice2"
    expect "installed once" 0 "installed: 8 groups" "$0" install "$t/twice" "$t/w-twice"
    cp "$t/twice/settings.json" "$t/twice.installed" && cp "$t/w-twice/settings.json.backup" "$t/twice.backup"
    expect "second install, same work folder: stops" 5 "already holds a backup" "$0" install "$t/twice" "$t/w-twice"
    expect "second install, new work folder: stops" 5 "already holds the spike" "$0" install "$t/twice" "$t/w-twice2"
    expect "second installs: the file is unchanged" 0 same same "$t/twice/settings.json" "$t/twice.installed"
    expect "second installs: the backup is unchanged" 0 same same "$t/w-twice/settings.json.backup" "$t/twice.backup"
    expect "after the second installs: uninstall is byte-identical" 0 "byte-identical" "$0" uninstall "$t/twice" "$t/w-twice"

    workdir "$t/w-badhad"
    expect "jq fails during uninstall: installed" 0 "installed: 8 groups" "$0" install "$t/badhad" "$t/w-badhad"
    cp "$t/badhad/settings.json" "$t/badhad.installed" && echo 'not json' >"$t/w-badhad/had.json"
    expect "jq fails during uninstall: stops" 5 "no JSON object" "$0" uninstall "$t/badhad" "$t/w-badhad"
    expect "jq fails during uninstall: the file is not emptied" 0 same same "$t/badhad/settings.json" "$t/badhad.installed"

    workdir "$t/w-changed"
    expect "changed while installed: install" 0 "installed: 8 groups" "$0" install "$t/changed" "$t/w-changed"
    jq --indent 2 '.model = "sonnet"' "$t/changed/settings.json" >"$t/next" && cat "$t/next" >"$t/changed/settings.json"
    expect "changed while installed: uninstall names the key" 4 '\["model"\]' "$0" uninstall "$t/changed" "$t/w-changed"
    expect "changed while installed: the change is kept" 0 sonnet jq -r .model "$t/changed/settings.json"
    expect "changed while installed: none of ours is left" 0 '^0$' \
        jq '[.hooks[][] | select(any(.hooks[]?; .command | contains("spike-hook.sh")))] | length' "$t/changed/settings.json"
    rm -rf "$t"
    return $fail
}

step=${1:-}
[ "$step" = selftest ] && { selftest; exit; }
[ $# = 3 ] || { sed -n '5,9p' "$0"; exit 2; }
dir=$2 work=$3
f="$dir/settings.json"
cmd="\"$work/spike-hook.sh\""

case $step in
precheck)
    command -v jq >/dev/null || { echo "STOP: jq is missing"; exit 3; }
    [ -L "$f" ] && { echo "STOP: settings.json is a symlink"; exit 3; }
    [ -f "$f" ] || { echo "STOP: settings.json does not exist"; exit 3; }
    jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { echo "STOP: settings.json is not a JSON object"; exit 3; }
    jq -e '(has("hooks") | not) or (.hooks | type == "object" and all(.[]; type == "array" and all(.[]; type == "object")))' \
        "$f" >/dev/null 2>&1 || { echo "STOP: hooks is not an object of lists of groups"; exit 3; }
    if [ "$(tail -c1 "$f" | od -An -tx1 | tr -d ' ')" = 0a ]; then nl='\n'; else nl=''; fi
    # shellcheck disable=SC2059 # $nl is the format on purpose: a newline or nothing.
    if cmp -s <(printf "%s$nl" "$(jq --indent 2 . "$f")") "$f"; then
        echo "precheck: two-space JSON, a round trip is byte-identical"
    else
        echo "STOP: a jq round trip changes the file's bytes"
        exit 3
    fi ;;
install)
    "$0" precheck "$dir" "$work" || exit
    # The path goes into a command every session sharing the file runs, so no quotes, $ or backticks.
    [[ "$work" =~ ^[A-Za-z0-9._/-]+$ ]] || stop "the work folder's path may hold only letters, digits and . _ / -"
    [ -x "$work/spike-hook.sh" ] || stop "copy spike-hook.sh into the work folder first"
    [ -e "$work/settings.json.backup" ] && stop "this work folder already holds a backup: uninstall first, or use a new one"
    jq -e '[(.hooks // {})[][] | select(any(.hooks[]?; .command | tostring | contains("spike-hook.sh")))] | length == 0' \
        "$f" >/dev/null || stop "settings.json already holds the spike's hook"
    cp -p "$f" "$work/settings.json.backup" || stop "could not back up settings.json"
    jq -c '{hooks: has("hooks"), events: ((.hooks // {}) | keys)}' "$f" >"$work/had.json" || stop "could not write had.json"
    put "$(jq --indent 2 --arg c "$cmd" --argjson ev "$events" \
        '.hooks //= {} | reduce $ev[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [{hooks: [{type: "command", command: $c, timeout: 5}]}]))' \
        "$work/settings.json.backup")"
    echo "installed: $(jq --arg c "$cmd" '[.hooks[][] | select(any(.hooks[]?; .command == $c))] | length' "$f") groups" ;;
uninstall)
    [ -f "$work/had.json" ] && [ -f "$work/settings.json.backup" ] || stop "this work folder holds no install"
    put "$(jq --indent 2 --arg c "$cmd" --argjson ev "$events" --slurpfile had "$work/had.json" '$had[0] as $h
        | reduce $ev[] as $e (.; if .hooks[$e] then .hooks[$e] |= map(select(any(.hooks[]?; .command == $c) | not)) else . end)
        | reduce $ev[] as $e (.; if (.hooks[$e] == []) and ($h.events | index($e) | not) then del(.hooks[$e]) else . end)
        | if (.hooks == {}) and ($h.hooks | not) then del(.hooks) else . end' "$f")"
    echo "left of ours: $(jq --arg c "$cmd" '[(.hooks // {})[][] | select(any(.hooks[]?; .command == $c))] | length' "$f")"
    if cmp -s "$f" "$work/settings.json.backup"; then
        echo "uninstall: byte-identical to the backup"
    else
        # Never restore the backup here: someone may have changed the file on purpose meanwhile.
        echo "uninstall: DIFFERENT from the backup. Top-level keys that differ:"
        jq -n -c --slurpfile a "$f" --slurpfile b "$work/settings.json.backup" \
            '[($a[0] | keys) + ($b[0] | keys) | unique[] | select($a[0][.] != $b[0][.])]'
        exit 4
    fi ;;
*)
    sed -n '5,9p' "$0"
    exit 2 ;;
esac
