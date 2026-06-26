local events = require("lib.core.event")
local actual = require("lib.core.blueprint.actual")
local registration_lib = require("control.registration")
local frame_lib = require("control.frame")
local op_lib = require("control.op.op")
local bpop_lib = require("control.op.blueprint")
local ws_lib = require("lib.core.world-state")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")

local get_thing_registration = registration_lib.get_thing_registration
local make_world_key = ws_lib.make_world_key
local EMPTY = tlib.EMPTY_STRICT
local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local NAME_TAG = constants.NAME_TAG
local BlueprintOp = bpop_lib.BlueprintOp

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
	local cursor_ghost = player.cursor_ghost --[[@as ItemIDAndQualityIDPair?]]
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
		bpop_lib.maybe_generate_blueprint_op(bp, player, surface, ev, ev.build_mode)
	end
)
