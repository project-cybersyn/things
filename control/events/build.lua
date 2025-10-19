local events = require("lib.core.event")
local frame_lib = require("control.frame")
local registration_lib = require("control.registration")
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local get_world_state = ws_lib.get_world_state

--------------------------------------------------------------------------------
-- Unify game events into generic build event, and generate creation ops.
--------------------------------------------------------------------------------

---@param ev EventData.script_raised_built|EventData.script_raised_revive|EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_entity_cloned|EventData.on_space_platform_built_entity
local function handle_generic_built(ev)
	local player = ev.player_index and game.get_player(ev.player_index) or nil
	local entity = ev.entity
	local name = entity.type == "entity-ghost" and entity.ghost_name
		or entity.name

	-- Early out if not a thing
	local registration = registration_lib.get_thing_registration(name)
	if not registration then return end

	-- Generate creation op.
	local frame = frame_lib.get_frame()
	local op = op_lib.Op:new(op_lib.OpType.CREATE, get_world_state(entity))
	frame:add_op(op)
end

events.bind(defines.events.on_built_entity, handle_generic_built)
events.bind(defines.events.on_robot_built_entity, handle_generic_built)
events.bind(defines.events.on_space_platform_built_entity, handle_generic_built)
events.bind(defines.events.script_raised_built, handle_generic_built)
events.bind(defines.events.script_raised_revive, handle_generic_built)
