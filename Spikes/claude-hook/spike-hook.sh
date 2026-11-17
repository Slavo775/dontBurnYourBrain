#!/bin/bash
# Spike for card #5: append one JSON line per Claude Code hook event to
# events.jsonl next to this script. It records which fields arrived and what
# the environment says about the terminal. It never records prompt text,
# replies or transcript content. It must never hold up or break a session,
# so it is quick and always exits 0.

exec 2>/dev/null
log="$(dirname "$0")/events.jsonl"
input=$(head -c 1048576)
command -v jq >/dev/null || exit 0

# Standard input is the JSON, not the terminal, so the terminal is read from
# the ancestors: pid, tty and executable name of each process up to launchd.
ancestors=$(ps -A -o pid=,ppid=,tty=,comm= | awk -v pid=$$ '
    { p = $1; parent[p] = $2; tty[p] = $3; $1 = $2 = $3 = ""; sub(/^ +/, "")
      n = split($0, part, "/"); comm[p] = part[n] }
    END { while ((pid in parent) && pid > 1) { print pid "\t" tty[pid] "\t" comm[pid]; pid = parent[pid] } }')

printf '%s' "$input" | jq -cRs --arg ancestors "$ancestors" '
    ($ancestors | split("\n") | map(select(length > 0) | split("\t")
        | {pid: (.[0] | tonumber), tty: .[1], comm: .[2]})) as $chain
    | (try fromjson catch null) as $in
    | {ts: (now * 1000 | floor), at: (now | strflocaltime("%H:%M:%S"))}
    + (if ($in | type) != "object" then {event: "invalid-input", bytes: length}
       else $in | {
           event: .hook_event_name,
           keys: keys,
           session_id, cwd, transcript_path, permission_mode, prompt_id,
           source, reason, model, notification_type, tool_name,
           agent_id, agent_type, agent_transcript_path, stop_hook_active,
           tool_input_keys: (.tool_input | if type == "object" then keys else null end),
           run_in_background: .tool_input.run_in_background?,
           subagent_type: .tool_input.subagent_type?,
           tool_status: .tool_response.status?,
           background_tasks: (.background_tasks | if type == "array"
               then map({id, type, status, agent_type}) else null end),
           session_crons: (.session_crons | if type == "array" then length else null end),
           prompt_kind: (.prompt | if type != "string" then null
               elif test("^<[A-Za-z_-]+") then "tag:" + capture("^<(?<t>[A-Za-z_-]+)").t
               else "typed" end)
       } | with_entries(select(.value != null)) end)
    + {
        tty: ([$chain[] | select(.tty != "??")][0].tty),
        env: ($ENV | with_entries(select(.key | test("^(TERM|TERM_PROGRAM|TERM_PROGRAM_VERSION|TERM_SESSION_ID|ITERM_SESSION_ID|LC_TERMINAL|LC_TERMINAL_VERSION|COLORTERM|__CFBundleIdentifier|XPC_SERVICE_NAME|CLAUDE_CONFIG_DIR|CLAUDE_PROJECT_DIR|CLAUDE_CODE_ENTRYPOINT|CLAUDECODE|CLAUDE_PID|CLAUDE_CODE_SESSION_ID|CLAUDE_CODE_SESSION_ATTENDED|CLAUDE_CODE_CHILD_SESSION|TMUX|TMUX_PANE)$")))),
        env_names: ($ENV | keys | map(select(test("^(TERM|ITERM|VSCODE|CURSOR|CLAUDE|__CF|XPC|LC_TERMINAL|KITTY|WEZTERM|ALACRITTY|GHOSTTY|TMUX|WARP|ZED)")))),
        ancestors: $chain
    }' >>"$log"
exit 0
