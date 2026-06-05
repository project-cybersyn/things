-- Events for extraction of blueprints.

local events = require("lib.core.event")
local extraction_lib = require("control.blueprint-extraction")
local actual = require("lib.core.blueprint.actual")
local strace = require("lib.core.strace")

events.bind(
	defines.events.on_player_setup_blueprint,
	---@param ev EventData.on_player_setup_blueprint
	function(ev)
		local player = game.get_player(ev.player_index)
		if not player then return end
		local bp = actual.get_actual_blueprint(player, ev.record, ev.stack)
		if not bp then return end
		local lazy_bp_to_world = ev.mapping
		if not lazy_bp_to_world or not lazy_bp_to_world.valid then
			strace.debug("Extract blueprint: no mapping")
			return
		end
		local bp_to_world = lazy_bp_to_world.get() --[[@as { [integer]: LuaEntity }|nil ]]
		if not bp_to_world then
			strace.debug("Extract blueprint: empty mapping")
			return
		end

		extraction_lib.extract_user_blueprint(bp, bp_to_world)
	end
)
