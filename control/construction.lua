local world_state = require("lib.core.world-state")

local make_key = world_state.make_world_key
local get_world_key = world_state.get_world_key

on_blueprint_extract(
	---@param bp Core.Blueprintish
	function(event, player, bp)
		debug_log("on_blueprint_extract", event)
		local lazy_bp_to_world = event.mapping
		if not lazy_bp_to_world or not lazy_bp_to_world.valid then
			debug_log("on_blueprint_extract: no mapping")
			return
		end
		local bp_to_world = lazy_bp_to_world.get() --[[@as { [integer]: LuaEntity }|nil ]]
		if not bp_to_world then
			debug_log("on_blueprint_extract: empty mapping")
			return
		end

		local extraction = Extraction:new(bp, bp_to_world)
		extraction:map_things()
		-- TODO: Thing-Thing relationships
		extraction:map_entities()

		extraction:destroy()
	end
)

on_blueprint_apply(
	---@param bp Core.Blueprintish
	function(player, bp, surface, event)
		debug_log("on_blueprint_apply", player, bp, surface, event)
		-- Create application record
		local application = Application:new(player, bp, surface, event)
		application:apply_overlapping_tags()
		application:destroy()
	end
)

on_pre_build_entity(function(event, player, entity_prototype, quality, surface)
	debug_log(
		"on_pre_build_entity",
		event,
		player,
		entity_prototype,
		quality,
		surface
	)
	-- Create prebuild record
	local prebuild = get_prebuild_player_state(player.index)
	local key = make_key(event.position, surface.index, entity_prototype.name)
	prebuild:mark_key_as_prebuilt(key)
end)

---@param event AnyFactorioBuildEventData
---@param ghost LuaEntity
---@param tags? Tags
---@param player? LuaPlayer
on_built_ghost(function(event, ghost, tags, player)
	debug_log("built_ghost", event, ghost, tags, player)

	-- Check for undo operation. (owned by player, no
	-- corresponding pre-build event)
	if player then
		local prebuild = get_prebuild_player_state(player.index)
		local key = world_state.get_world_key(ghost)
		if not prebuild:was_key_prebuilt(key) then
			-- Likely an undo/redo ghost
			if maybe_undo(ghost, key, player) then
				debug_log("built_ghost: ghost from undo/redo", key)
				return
			end
		end
	end

	-- Ghost is a tagged bplib object from a blueprint
	if tags and tags["@i"] then
		local thing = Thing:new()
		thing:built_as_tagged_ghost(ghost, tags)
		return
	end

	-- Ghost is a new unthing
	debug_log("built_ghost: ghost is a new unthing")
	script.raise_event("things-on_unthing_built", {
		entity = ghost,
		prototype_name = ghost.ghost_name,
		prototype_type = ghost.ghost_type,
	})
end)

---@param event AnyFactorioBuildEventData
---@param entity LuaEntity
---@param tags? Tags
---@param player? LuaPlayer
on_built_real(function(event, entity, tags, player)
	debug_log("built_real", event, entity, tags)

	-- Check for undo operation. (owned by player, no
	-- corresponding pre-build event)
	if player then
		local prebuild = get_prebuild_player_state(player.index)
		local key = world_state.get_world_key(entity)
		if not prebuild:was_key_prebuilt(key) then
			-- Likely an undo/redo ghost
			if maybe_undo(entity, key, player) then
				debug_log("built_real: real from undo/redo", key)
				return
			end
		end
	end

	-- Real is a tagged bplib object from a blueprint.
	-- (It must've been built via cheat/editor because it skipped ghost state)
	if tags and tags["@i"] then
		local thing = Thing:new()
		thing:built_as_tagged_real(entity, tags)
		return
	end

	-- Real is a revived ghost thing
	if tags and tags["@ig"] then
		local thing_id = tags["@ig"]
		debug_log("built_real: real is a revived ghost thing with id", thing_id)
		local thing = get_thing(thing_id)
		if thing then
			thing:revived_from_ghost(entity, tags)
		else
			debug_log(
				"built_real: real is a revived ghost Thing but we don't know about it (bad news)",
				thing_id
			)
		end
		return
	end

	-- Real is an unthing
	debug_log("built_real: real is a new unthing")
	script.raise_event("things-on_unthing_built", {
		entity = entity,
		prototype_name = entity.name,
		prototype_type = entity.type,
	})
end)

on_entity_cloned(function(event) debug_log("on_entity_cloned", event) end)

on_undo_applied(function(event)
	local player = game.get_player(event.player_index)
	if not player then return end
	local urs = player.undo_redo_stack
	if urs.get_undo_item_count() > 0 then
		debug_log("undo_applied. Top undo item is:", urs.get_undo_item(1))
	end
	local vups = get_undo_player_state(event.player_index)
	if not vups then return end
	vups:on_undo_applied(event.actions)
end)

on_redo_applied(function(event)
	local vups = get_undo_player_state(event.player_index)
	if not vups then return end
	vups:on_redo_applied(event.actions)
end)

-- Death

on_unified_pre_destroy(function(event, entity, player)
	-- TODO: do we need to hook pre destroy?
end)

on_entity_marked(function(event, entity, player)
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

on_unified_destroy(function(event, entity, player, leave_tombstone)
	local un = entity.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
	-- If the thing was destroyed by an undoable player action, create an
	-- immediate tombstone for it.
	if player and leave_tombstone then
		--- XXX: UNDOABLE ACTION - Player mines entity.
		debug_log("thing destroyed by undoable player action, leaving tombstone")
		debug_undo_stack(player)
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

on_entity_died(function(event)
	local un = event.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then
		debug_log("unthing died")
		return
	end
	local ghost = event.ghost
	if ghost then
		debug_log("entity died leaving a ghost")
		thing:died_leaving_ghost(ghost)
	else
		debug_log("entity died leaving no ghost")
		-- Died leaving no ghost; safe to destroy Thing altogether.
		thing:destroy()
	end
end)

-- Configuration

on_player_flipped_entity(function(event, entity)
	debug_log("on_player_flipped_entity", event)
	debug_log("entity flipped", entity.name, entity.direction, entity.mirroring)
end)

on_player_rotated_entity(function(event, entity)
	debug_log("on_player_rotated_entity", event)
	debug_log("entity rotated", entity.name, entity.direction, entity.mirroring)
end)
