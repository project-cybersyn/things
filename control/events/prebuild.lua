local events = require("lib.core.event")
local actual = require("lib.core.blueprint.actual")
local registration_lib = require("control.registration")
local frame_lib = require("control.frame")
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")

local get_thing_registration = registration_lib.get_thing_registration
local make_world_key = ws_lib.make_world_key

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
		debug_log(entity_placed.name, "prebuilt by player", player.index, "at", key)
	end
)

--------------------------------------------------------------------------------
-- NARROW PHASE - BLUEPRINT
--------------------------------------------------------------------------------
