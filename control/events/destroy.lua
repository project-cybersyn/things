local events = require("lib.core.event")
local thing_lib = require("control.thing")
local strace = require("lib.core.strace")
local frame_lib = require("control.frame")
local constants = require("control.constants")
local ws_lib = require("lib.core.world-state")

local MfdOp = require("control.op.mfd").MfdOp
local DestroyOp = require("control.op.destroy").DestroyOp

local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local get_thing_by_id = thing_lib.get_by_id
local get_thing_by_unit_number = thing_lib.get_by_unit_number
local get_world_state = ws_lib.get_world_state

-- Handle death of a Thing that leaves behind a ghost.
events.bind(
	defines.events.on_post_entity_died,
	---@param ev EventData.on_post_entity_died
	function(ev)
		local thing = get_thing_by_unit_number(ev.unit_number)
		if not thing then return end
		local ghost = ev.ghost
		if ghost then
			-- Died leaving ghost
			if thing.state == "real" then
				-- XXX: Do we need a frame here?
				thing:set_entity(ghost)
				thing:set_state("ghost")
			else
				strace.error(
					"Thing in non-real state died leaving ghost. Should be impossible.",
					thing
				)
			end
		else
			-- Died without leaving ghost; will be totally destroyed.
		end
	end
)

-- Create an MFD record if a Thing is MFD.
events.bind(
	defines.events.on_marked_for_deconstruction,
	---@param ev EventData.on_marked_for_deconstruction
	function(ev)
		local entity = ev.entity
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then return end
		local frame = frame_lib.get_frame()
		frame:add_op(MfdOp:new(entity, nil, thing, ev.player_index))
	end
)

---Create a Destroy record if a Thing is destroyed.
---@param ev EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy
local function handle_destroyed(ev)
	local entity = ev.entity
	local thing = get_thing_by_unit_number(entity.unit_number)
	if not thing then return end
	local frame = frame_lib.get_frame()
	frame:add_op(DestroyOp:new(entity, thing, ev.player_index))
end

events.bind(defines.events.on_player_mined_entity, handle_destroyed)
events.bind(defines.events.on_robot_mined_entity, handle_destroyed)
events.bind(defines.events.on_space_platform_mined_entity, handle_destroyed)
events.bind(defines.events.script_raised_destroy, handle_destroyed)
