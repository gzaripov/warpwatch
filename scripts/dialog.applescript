on run argv
	-- argv: {message, appName, iconNumber, giveUpSeconds, focusUrl}
	set msg to item 1 of argv
	set appName to item 2 of argv
	set iconNum to (item 3 of argv) as integer
	set giveUp to (item 4 of argv) as integer
	set focusUrl to ""
	if (count of argv) > 4 then set focusUrl to item 5 of argv
	-- Owned by System Events so it floats on top even when no app is frontmost.
	tell application "System Events"
		activate
		set r to display dialog msg with title "Claude Code" buttons {"Закрыть", "Открыть Warp"} default button "Открыть Warp" with icon iconNum giving up after giveUp
	end tell
	-- Only act on an explicit click (not on timeout). Prefer the per-tab deep
	-- link so we land on the exact session, not just whatever tab is frontmost.
	if (gave up of r) is false and (button returned of r) is "Открыть Warp" then
		if focusUrl is not "" then
			do shell script "open " & quoted form of focusUrl
		else
			tell application appName to activate
		end if
	end if
end run
