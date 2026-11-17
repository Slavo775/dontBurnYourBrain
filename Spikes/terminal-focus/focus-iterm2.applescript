-- Brings forward the iTerm2 session whose unique ID is the argument: selects
-- its tab and session, brings its window to the front, un-minimizing it when
-- needed, and activates iTerm2. Reads only the unique ID of other sessions.
-- When no session has that ID, it changes nothing and fails with exit status 1.
-- Usage: osascript focus-iterm2.applescript <UUID>   (or the whole ITERM_SESSION_ID, w0t0p0:<UUID>)
on run argv
	if (count of argv) is not 1 then error "usage: osascript focus-iterm2.applescript <UUID>" number 2
	set target to item 1 of argv
	if target contains ":" then
		set AppleScript's text item delimiters to ":"
		set target to last text item of target
		set AppleScript's text item delimiters to ""
	end if
	tell application "iTerm2"
		repeat with winId in (get id of windows)
			-- One list per tab, one ID per session (split pane) in that tab.
			set idsPerTab to unique ID of sessions of tabs of window id winId
			repeat with t from 1 to count of idsPerTab
				set ids to item t of idsPerTab
				repeat with s from 1 to count of ids
					if item s of ids is target then
						set w to window id winId
						if miniaturized of w then set miniaturized of w to false
						select w
						select tab t of w
						select session s of tab t of w
						activate
						return "focused " & target & " in iTerm2 window " & winId
					end if
				end repeat
			end repeat
		end repeat
	end tell
	error "no iTerm2 session has the unique ID " & target number 1
end run
