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
set -uo pipefail

events='["SessionStart","UserPromptSubmit","PermissionRequest","Notification","Stop","SubagentStart","SubagentStop","SessionEnd"]'

# Writes JSON in place, which keeps the inode and the mode, and ends it with a newline only if the
# backup did.
put() {
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
        expect "$p: install adds 8 groups" 0 "installed: 8 groups" "$0" install "$t/$p" "$t/w-$p"
        expect "$p: uninstall leaves it byte-identical" 0 "byte-identical" "$0" uninstall "$t/$p" "$t/w-$p"
    done
    expect "hand-formatted file: precheck stops" 3 "round trip" "$0" precheck "$t/hand" "$t/w-hand"
    expect "symlink: precheck stops" 3 "symlink" "$0" precheck "$t/link" "$t/w-link"
    expect "missing file: precheck stops" 3 "does not exist" "$0" precheck "$t/missing" "$t/w-missing"
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
    mkdir -p "$work"
    cp -p "$f" "$work/settings.json.backup"
    jq -c '{hooks: has("hooks"), events: ((.hooks // {}) | keys)}' "$f" >"$work/had.json"
    put "$(jq --indent 2 --arg c "$cmd" --argjson ev "$events" \
        '.hooks //= {} | reduce $ev[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [{hooks: [{type: "command", command: $c, timeout: 5}]}]))' \
        "$work/settings.json.backup")"
    echo "installed: $(jq --arg c "$cmd" '[.hooks[][] | select(any(.hooks[]?; .command == $c))] | length' "$f") groups" ;;
uninstall)
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
