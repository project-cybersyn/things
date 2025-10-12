local world_state = require("lib.core.world-state")
local bind = require("control.events.typed").bind
local op_lib = require("control.infrastructure.operation")
local mop_lib = require("control.infrastructure.mass-operation")
local uop_lib = require("control.infrastructure.undo-application")
local constants = require("control.constants")

local ConstructionOperation = op_lib.ConstructionOperation
local make_key = world_state.make_world_key
local get_world_key = world_state.get_world_key

-- Pre-build of a single entity that is not part of a blueprint.
bind(
	"pre_build_entity",
	function(ev, player, entity_prototype, quality, surface)
		-- Filter out non-Things.
		if not get_thing_registration(entity_prototype.name) then return end

		debug_log(
			"on_pre_build_entity: Prebuilt a Thing",
			ev,
			player,
			entity_prototype,
			quality,
			surface
		)

		-- Create prebuild record
		local prebuild = get_prebuild_player_state(player.index)
		local key = make_key(ev.position, surface.index, entity_prototype.name)
		prebuild:mark_key_as_prebuilt(key)
	end
)

bind("built_ghost", function(ev, ghost, tags, player)
	-- Filter out non-Things.
	if not get_thing_registration(ghost.ghost_name) then return end
	debug_log("built_ghost", ev, ghost, tags, player)

	local op = ConstructionOperation:new(ghost, tags, player)

	-- Try to associate this build with an existing mass operation.
	-- If it is included in one, the MO will handle the rest of the logic.
	if mop_lib.try_include_in_all(op, game.ticks_played) then return end

	-- Try to generate a new Undo operation from this build.
	local uop = uop_lib.maybe_begin_undo_operation(op)
	if uop then return end

	-- Ghost is a new specimen of this Thing type.
	debug_log("built_ghost: ghost is a new Thing")
	thingify_entity(ghost, op.key)
end)

---@param ev AnyFactorioBuildEventData
---@param entity LuaEntity
---@param tags? Tags
---@param player? LuaPlayer
bind("built_real", function(ev, entity, tags, player)
	-- Filter out non-Things.
	if not get_thing_registration(entity.name) then return end
	debug_log("built_real", ev, entity, tags)

	local op = ConstructionOperation:new(entity, tags, player)

	-- Ladder of possible cases:
	-- 1) Thing was built as part of an existing mass operation
	-- (undo, blueprint, c/p)
	if mop_lib.try_include_in_all(op, game.ticks_played) then return end

	-- 2) Thing is beginning a new Undo operation, which we cannot detect
	-- in advance due to lack of pre-undo event.
	local uop = uop_lib.maybe_begin_undo_operation(op)
	if uop then return end

	-- 3) Thing is the revival of a ghost Thing
	if mark_revived_ghost(op) then return end

	-- 4) Thing is newly constructed
	debug_log("built_real: real is a new Thing")
	thingify_entity(entity, op.key)
end)

bind("entity_cloned", function(event)
	debug_log("on_entity_cloned", event)
	-- TODO: impl. if original is a thing, make a new thing. respect ghostiness
end)

---@param event EventData.on_undo_applied|EventData.on_redo_applied
local function undo_redo_applied(event)
	local mop = mop_lib.find("undo", event.player_index, game.ticks_played) --[[@as things.UndoApplication?]]
	if not mop then
		debug_log("undo_applied: no UndoApplication found")
		return
	end
	mop:complete(event.actions)
end

bind("undo_applied", undo_redo_applied)
bind("redo_applied", undo_redo_applied)

-- Death

bind("unified_pre_destroy", function(event, entity, player)
	-- TODO: do we need to hook pre destroy?
end)

bind("entity_marked", function(event, entity, player)
	local un = entity.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
	-- XXX: UNDOABLE ACTION - Player mark for deconstruction
	local vups = get_undo_player_state(player.index)
	if not vups then return end
	vups:reconcile_if_needed()
	local marker = UndoMarker:new(entity, thing, true, "deconstruction")
	vups:add_marker(marker)
end)

bind("unified_destroy", function(event, entity, player, leave_tombstone)
	local un = entity.unit_number
	if not un then return end
	-- If marked ghost, clear its world key mapping
	if entity.type == "entity-ghost" then
		local key = get_world_key(entity)
		clear_thing_ghost(key)
	end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
	-- If the thing was destroyed by an undoable player action, create an
	-- immediate tombstone for it.
	if player and leave_tombstone then
		--- XXX: UNDOABLE ACTION - Player mines entity.
		-- debug_log("thing destroyed by undoable player action, leaving tombstone")
		-- debug_undo_stack(player)
		local vups = get_undo_player_state(player.index)
		if vups then
			vups:reconcile_if_needed()
			local marker = UndoMarker:new(entity, thing, true, "deconstruction")
			vups:add_marker(marker)
		end
	end
	-- Notify the thing that its entity was destroyed. (Logic here will
	-- check for tombstone state and act accordingly.)
	thing:entity_destroyed(entity)
end)

bind("entity_died", function(event)
	local un = event.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
	local ghost = event.ghost
	if ghost then
		debug_log("Thing died leaving a ghost", thing.id)
		thing:died_leaving_ghost(ghost)
	else
		debug_log("Thing died leaving no ghost and will be destroyed", thing.id)
		-- Died leaving no ghost; safe to destroy Thing altogether.
		thing:destroy()
	end
end)

-- Configuration

-- on_player_flipped_entity(function(event, entity)
-- 	debug_log("on_player_flipped_entity", event)
-- 	debug_log("entity flipped", entity.name, entity.direction, entity.mirroring)
-- end)

-- on_player_rotated_entity(function(event, entity)
-- 	debug_log("on_player_rotated_entity", event)
-- 	debug_log("entity rotated", entity.name, entity.direction, entity.mirroring)
-- end)
