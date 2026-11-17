-- Brings forward the Terminal tab whose tty is the argument: selects the tab,
-- brings its window to the front, un-minimizing it when needed, and activates
-- Terminal. Reads only the tty of other tabs. When no tab holds that tty, it
-- changes nothing and fails with exit status 1.
-- Usage: osascript focus-terminal.applescript /dev/ttysNNN   (or ttysNNN)
on run argv
	if (count of argv) is not 1 then error "usage: osascript focus-terminal.applescript /dev/ttysNNN" number 2
	set target to item 1 of argv
	if target does not start with "/dev/" then set target to "/dev/" & target
	tell application "Terminal"
		repeat with winId in (get id of windows)
			set ttys to tty of tabs of window id winId
			repeat with i from 1 to count of ttys
				if item i of ttys is target then
					set w to window id winId
					if miniaturized of w then set miniaturized of w to false
					set selected of tab i of w to true
					set index of w to 1
					activate
					return "focused " & target & " in Terminal window " & winId
				end if
			end repeat
		end repeat
	end tell
	error "no Terminal tab has the tty " & target number 1
end run
