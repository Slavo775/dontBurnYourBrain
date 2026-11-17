#!/bin/bash
# Runs inside a spike tab. Writes what a hook in this tab would see to the file
# named in $1, sets the tab's title to "dontburn-spike $2 $3", then leaves a plain shell in the tab so
# the tab stays open. The shell keeps this process's pid, so "pid" is the process
# that holds the tty.
{
    echo "tty=$(tty)"
    echo "pid=$$"
    echo "iterm=${ITERM_SESSION_ID:-}"
} >"$1"
# iTerm2 ignores a session name set by AppleScript once a job runs, but keeps this.
printf '\033]0;dontburn-spike %s %s\007' "$2" "$3"
exec /bin/bash --noprofile --norc -i
