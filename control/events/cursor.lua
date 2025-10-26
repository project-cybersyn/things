local events = require("lib.core.event")
local reg_lib = require("control.registration")

-- Handle cursor stack clearing for Things that disallow being in the cursor.
events.bind(
	"on_player_cursor_stack_changed",
	---@param event EventData.on_player_cursor_stack_changed
	function(event)
		local player = game.get_player(event.player_index)
		if not player then return end

		-- Check if the cursor stack contains any Things that disallow being in the cursor
		local cursor_stack = player.cursor_stack
		if not cursor_stack or not cursor_stack.valid_for_read then return end

		local reg = reg_lib.get_thing_registration(cursor_stack.name)
		if not reg then return end

		if reg.allow_in_cursor == "never" then player.cursor_stack.clear() end
	end
)
