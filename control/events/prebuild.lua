local events = require("lib.core.event")
local actual = require("lib.core.blueprint.actual")
local registration_lib = require("control.registration")
local frame_lib = require("control.frame")
local op_lib = require("control.op.op")
local BlueprintOp = require("control.op.blueprint").BlueprintOp
local ws_lib = require("lib.core.world-state")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")

local get_thing_registration = registration_lib.get_thing_registration
local make_world_key = ws_lib.make_world_key
local EMPTY = tlib.EMPTY_STRICT
local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local NAME_TAG = constants.NAME_TAG

--------------------------------------------------------------------------------
-- BROADPHASE
-- Classify prebuild operation.
--------------------------------------------------------------------------------

events.bind(defines.events.on_pre_build, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end
	-- Blueprint
	if player.is_cursor_blueprint() then
		local bp = actual.get_actual_blueprint(
			player,
			player.cursor_record,
			player.cursor_stack
		)
		if not bp then return end
		return events.raise(
			"things.pre_build_blueprint",
			ev,
			player,
			bp,
			player.surface
		)
	end
	-- Item with entity place result
	local stack = player.cursor_stack
	if stack and stack.valid_for_read then
		local entity_placed = stack.prototype.place_result
		if entity_placed then
			return events.raise(
				"things.pre_build_entity",
				ev,
				player,
				entity_placed,
				stack.quality,
				player.surface
			)
		end
	end
	-- Ghost cursor
	local cursor_ghost = player.cursor_ghost
	if cursor_ghost then
		local entity_placed = cursor_ghost.name.place_result
		if entity_placed then
			return events.raise(
				"things.pre_build_entity",
				ev,
				player,
				entity_placed,
				cursor_ghost.quality --[[@as LuaQualityPrototype]],
				player.surface
			)
		end
	end
end)

--------------------------------------------------------------------------------
-- NARROW PHASE - ENTITIES
-- Begin frame and mark prebuilds.
--------------------------------------------------------------------------------

events.bind(
	"things.pre_build_entity",
	---@param ev EventData.on_pre_build
	---@param player LuaPlayer
	---@param entity_placed LuaEntityPrototype
	---@param quality LuaQualityPrototype
	---@param surface LuaSurface
	function(ev, player, entity_placed, quality, surface)
		-- Filter out non Things
		local registration = get_thing_registration(entity_placed.name)
		if not registration then return end
		-- Begin frame
		local frame = frame_lib.get_frame()
		-- Mark prebuilt entity
		local key = make_world_key(ev.position, surface.index, entity_placed.name)
		frame:mark_prebuild(key, player.index)
		strace.debug(
			frame.debug_string,
			"prebuild by player",
			player.index,
			"at",
			key
		)
	end
)

--------------------------------------------------------------------------------
-- NARROW PHASE - BLUEPRINT
--------------------------------------------------------------------------------

events.bind(
	"things.pre_build_blueprint",
	---@param ev EventData.on_pre_build
	---@param player LuaPlayer
	---@param bp Core.Blueprintish
	---@param surface LuaSurface
	function(ev, player, bp, surface)
		strace.debug("things.pre_build_blueprint by", player.name)

		local entities = bp.get_blueprint_entities()
		if (not entities) or (#entities == 0) then return end

		-- Check for Things
		---@type table<uint, things.InternalBlueprintEntityInfo>
		local by_index = {}
		for i, bp_entity in pairs(entities) do
			local tags = bp_entity.tags or EMPTY
			local thing_name = tags[NAME_TAG] --[[@as string?]]
			local bplid = tags[LOCAL_ID_TAG]
			if bplid then
				if not thing_name then thing_name = bp_entity.name end
				local registration = get_thing_registration(thing_name)
				if registration then
					local info = {
						bp_entity = bp_entity,
						bp_index = i,
						bplid = bplid,
						thing_name = thing_name,
					}
					by_index[i] = info
				else
					strace.debug(
						"things.pre_build_blueprint: entity",
						bp_entity,
						"has unregistered thing name",
						thing_name,
						"ignoring."
					)
				end
			end
		end

		-- Early out if no Things
		if not next(by_index) then
			strace.debug("things.pre_build_blueprint: no Things found in blueprint")
			return
		end

		-- Generate frame and op
		local frame = frame_lib.get_frame()
		local op =
			BlueprintOp:new(frame, ev, player, bp, surface, entities, by_index)
		frame:add_op(op)
	end
)
