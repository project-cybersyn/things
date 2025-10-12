--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

require("lib.core.debug-log")
set_print_debug_log(true)

local event = require("lib.core.event")

require("control.mod-data")
require("control.storage")
require("control.settings")

require("control.state.player")

require("control.thing")
require("control.graph")
require("control.prebuild")
require("control.virtual-undo")
require("control.debug-overlay")

-- Event handlers
require("control.events.blueprinting")
require("control.events.construction")
require("control.events.orientation")
require("control.events.broadphase")
require("control.events.custom")

require("control.undo-stack-debugger")

-- Remote interface
require("remote-interface")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

-- API

-- Commands

-- XXX: remove
commands.add_command(
	"things-debug-undo-stack",
	"Debug undo stack",
	function(cmd)
		local player = game.get_player(cmd.player_index)
		if not player then return end
		local vups = get_undo_player_state(player.index)
		if not vups then return end
		debug_undo_stack(player)
		debug_log("Top markers", vups.top_marker_set)
	end
)

event.bind("things-click", function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end
	if player.selected and player.selected.valid then
		local thing = get_thing_by_unit_number(player.selected.unit_number)
		if thing then
			debug_log("Clicked Thing", thing.id, thing.entity, thing.state)
		else
			debug_log("Clicked entity is not a Thing", player.selected)
		end
	else
		debug_log("Nothing selected")
	end
end)
