#!/bin/sh
# Spike for card #7. Run it in the integrated terminal of a Dev Container window: `sh probe.sh vscode`
# or `sh probe.sh cursor`. It writes probe-<editor>.txt next to itself: where this terminal runs, the
# names of the editor's environment variables (values only for the three named below), which editor
# server is on PATH, and the chain of parent processes. Nothing else from the environment.

out="$(dirname "$0")/probe-${1:-unknown}.txt"
{
    echo "kernel=$(uname -s) hostname=$(hostname) pwd=$(pwd)"
    echo "TERM_PROGRAM=${TERM_PROGRAM:-unset} __CFBundleIdentifier=${__CFBundleIdentifier:-unset}"
    echo "REMOTE_CONTAINERS=${REMOTE_CONTAINERS:-unset}"
    echo "names: $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' \
        | grep -E '^(VSCODE|REMOTE|CURSOR|TERM|__CF|CLAUDE|DEVCONTAINER)' | sort | tr '\n' ' ')"
    echo "server on PATH: $(echo "$PATH" | tr ':' '\n' | grep -oE '\.(vscode|cursor)-server' | sort -u | tr '\n' ' ')"
    # The image has no ps, so the chain is read from /proc: the name, then the parent's pid.
    pid=$$
    while [ "$pid" -gt 1 ] 2>/dev/null; do
        printf '%s <- ' "$(cat "/proc/$pid/comm")"
        pid=$(sed 's/.*) [A-Za-z] \([0-9]*\) .*/\1/' "/proc/$pid/stat")
    done
    echo "init"
} >"$out"
echo "wrote $out"
