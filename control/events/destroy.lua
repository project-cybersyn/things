local events = require("lib.core.event")
local thing_lib = require("control.thing")
local strace = require("lib.core.strace")
local frame_lib = require("control.frame")
local MfdOp = require("control.op.mfd").MfdOp
local DestroyOp = require("control.op.destroy").DestroyOp

---@type things.Storage
storage = storage --[[@as things.Storage]]

local get_thing_by_unit_number = thing_lib.get_by_unit_number

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

---Ghosts don't fire MFD or Destroy events when MFD.
---Therefore we must handle this event and treat it as a DestroyOp.
events.bind(
	defines.events.on_pre_ghost_deconstructed,
	---@param ev EventData.on_pre_ghost_deconstructed
	function(ev)
		local entity = ev.ghost
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then return end
		local frame = frame_lib.get_frame()
		frame:add_op(DestroyOp:new(entity, thing, ev.player_index))
	end
)

local TARGET_TYPE_ENTITY = defines.target_type.entity

---Last-resort handler for destroyed entities that don't fire any of the above events.
events.bind(
	defines.events.on_object_destroyed,
	---@param ev EventData.on_object_destroyed
	function(ev)
		if ev.type ~= TARGET_TYPE_ENTITY then return end
		local unit_number = ev.useful_id
		local thing = storage.things_by_unit_number[unit_number]
		if thing then
			strace.warn(
				"on_object_destroyed: Thing ID",
				thing.id,
				"with unit_number",
				unit_number,
				"was caught by an on_object_destroyed fallthrough. This is a possible referential integrity issue, bug, or scripted silent destruction by another mod."
			)

			thing:tombstone()
		end
		remove_unthing_child(unit_number, true, false)
		storage.trigger_entities[unit_number] = nil
	end
)
