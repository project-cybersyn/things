local events = require("lib.core.event")
local frame_lib = require("control.frame")
local registration_lib = require("control.registration")
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local thing_lib = require("control.thing")
local CreateOp = require("control.op.create").CreateOp
local strace = require("lib.core.strace")
local tu_lib = require("control.util.tags")

local get_migrated_tags = tu_lib.get_migrated_tags
local get_initial_tags = tu_lib.get_initial_tags
local get_thing_by_id = thing_lib.get_by_id
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local TAGS_TAG = constants.TAGS_TAG
local NAME_TAG = constants.NAME_TAG
local BLUEPRINT_TAG_SET = constants.BLUEPRINT_TAG_SET
local EMPTY = tlib.EMPTY_STRICT
local get_world_state = ws_lib.get_world_state
local get_thing_registration = registration_lib.get_thing_registration
local should_intercept_build = registration_lib.should_intercept_build
local CREATE_OP = op_lib.OpType.CREATE

--------------------------------------------------------------------------------
-- Unify game events into generic build event, and generate creation ops.
--------------------------------------------------------------------------------

---@param ev EventData.script_raised_built|EventData.script_raised_revive|EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_entity_cloned|EventData.on_space_platform_built_entity
local function handle_generic_built(ev)
	local player = ev.player_index and game.get_player(ev.player_index) or nil
	local entity = ev.entity
	local is_ghost = entity.type == "entity-ghost"
	local name = is_ghost and entity.ghost_name or entity.name
	local tags = (is_ghost and entity.tags or ev.tags) or EMPTY

	-- Check if a ghost is being revived.
	local revive_thing_id = tags[GHOST_REVIVAL_TAG] --[[@as uint64?]]
	if revive_thing_id then
		if not is_ghost then
			local revive_thing = get_thing_by_id(revive_thing_id)
			if revive_thing then
				if revive_thing.state ~= "ghost" then
					error(
						"Thing with revive tag is not in ghost state. Should be impossible."
					)
				else
					local frame = frame_lib.get_frame()
					strace.debug(
						frame.debug_string,
						"Reviving ghost of Thing ID",
						revive_thing_id
					)
					revive_thing:set_entity(entity)
					revive_thing:set_state("real")
					return
				end
			end
		else
			strace.debug(
				"handle_generic_built: ghost was initialized with a revive tag. this is probably jank from an undo; removing it."
			)
			tags[GHOST_REVIVAL_TAG] = nil
			entity.tags = tags
		end
	end

	-- Early out if not a thing
	local registration = get_thing_registration(tags[NAME_TAG] --[[@as string?]])
		or should_intercept_build(name)
	if not registration then return end

	-- Perform tag migration
	local real_tags = get_migrated_tags(tags, registration)
	if (not real_tags) or (not next(real_tags)) then
		real_tags = get_initial_tags(entity, registration, player)
	end

	local frame = frame_lib.get_frame()
	local ws = nil

	-- Check for a create_op already existing for this entity.
	-- This means a ghost was snap-revived.
	if not is_ghost then
		ws = get_world_state(entity)
		local existing_create_op = frame.op_set:findkt_first(ws.key, CREATE_OP) --[[@as things.CreateOp?]]
		if existing_create_op then
			strace.debug(
				frame.debug_string,
				"Found existing CreateOp for entity; assuming inline snap-revival",
				ws.key
			)
			existing_create_op.entity = entity
			existing_create_op.tags = real_tags
			return
		end
	end

	-- Generate creation op.
	local op = CreateOp:new(entity, ws)
	op.player_index = ev.player_index
	op.name = registration.name
	op.tags = real_tags
	frame:add_op(op)
end

events.bind(defines.events.on_built_entity, handle_generic_built)
events.bind(defines.events.on_robot_built_entity, handle_generic_built)
events.bind(defines.events.on_space_platform_built_entity, handle_generic_built)
events.bind(defines.events.script_raised_built, handle_generic_built)
events.bind(defines.events.script_raised_revive, handle_generic_built)
