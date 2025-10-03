--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

require("lib.core.debug-log")
set_print_debug_log(true)

require("control.mod-data")
require("control.storage")
require("control.settings")

require("control.thing")
require("control.graph")
require("control.prebuild")
require("control.virtual-undo")
require("control.extraction")
require("control.application")
require("control.debug-overlay")
require("control.remote")

-- Event handlers
require("control.events.blueprinting")
require("control.events.construction")
require("control.events.broadphase")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

-- API

remote.add_interface("things", _G.remote_interface)

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
		local urs = player.undo_redo_stack
		if urs.get_undo_item_count() > 0 then
			debug_log("Top undo item:", urs.get_undo_item(1))
		end
		debug_log("Top markers", vups.top_marker_set)
	end
)
