local tlib = require("lib.core.table")
local elib = require("lib.core.entities")

-- Synthesis of construction events

on_blueprint_extract(function(event, player, bp)
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

	local extraction = Extraction:new()

	-- Assign internal IDs to entities in the blueprint we know about
	for idx, entity in pairs(bp_to_world) do
		if (not entity.valid) or not entity.unit_number then goto continue end
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then goto continue end
		debug_log("on_blueprint_extract: known entity in blueprint", thing, entity)
		local local_id = extraction:map(thing)
		local tags = tlib.assign({}, thing.tags)
		tags["@i"] = local_id
		tags["@ig"] = nil
		bp.set_blueprint_entity_tags(idx, tags)
		::continue::
	end
	-- Remap parent/child relationships
	-- Store graph relationships

	extraction:destroy()
end)

on_blueprint_apply(function(player, blueprint, surface, event)
	debug_log("on_blueprint_apply", player, blueprint, surface, event)
	-- Create application record
end)

on_pre_build_from_item(
	function(event, player) debug_log("on_pre_build_from_item", event, player) end
)

---@param event AnyFactorioBuildEventData
---@param ghost LuaEntity
---@param tags? Tags
---@param player? LuaPlayer
local function built_ghost(event, ghost, tags, player)
	debug_log("built_ghost", event, ghost, tags, player)
	if player then
		debug_log("built_ghost: player is", player.name)
		-- debug_log(
		-- 	"built_ghost: undo stack is",
		-- 	player.undo_redo_stack.get_undo_item(1)
		-- )
	end
	-- Check if ghost is a potential undo over a tombstone
	-- Ghost is someone we knew who died
	local known = get_thing_by_unit_number(ghost.ghost_unit_number)
	if known then
		debug_log("built_ghost: ghost of a dead bplib entity:", known)
		return
	end
	-- Ghost is a tagged bplib object from a blueprint
	if tags and tags["@i"] then
		local local_id = tags["@i"] --[[@as int]]
		debug_log(
			"built_ghost: ghost from a bplib blueprint with local_id",
			local_id
		)
		-- Start a file on it
		local erec = Thing:new()
		erec.entity = ghost
		erec.local_id = local_id
		-- Remove the tag
		tags["@i"] = nil
		tags["@ig"] = erec.id
		ghost.tags = tags
		erec.tags = tags
		erec:set_state("ghost_initial")
		return
	end
	-- Ghost is a new unthing
	debug_log("built_ghost: ghost is a new unthing")
	script.raise_event("things-on_unthing_built", {
		entity = ghost,
		prototype_name = ghost.ghost_name,
		prototype_type = ghost.ghost_type,
	})
end

local function built_real(event, entity, tags)
	debug_log("built_real", event, entity, tags)
	-- Real is a tagged bplib object from a blueprint.
	-- (It must've been built via cheat/editor because it skipped ghost state)
	if tags and tags["@i"] then
		local local_id = tags["@i"]
		debug_log("built_real: real from a bplib blueprint with local_id", local_id)
		-- Start a file on it
		local thing = Thing:new()
		thing.entity = entity
		thing.local_id = local_id
		-- Remove the tag
		tags["@i"] = nil
		tags["@ig"] = thing.id
		thing.tags = tags
		thing:set_state("alive_initial")
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
				"built_real: real is a revived ghost thing but we don't know about it",
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
end

on_unified_build(function(event, entity, tags, player)
	debug_log("on_unified_build", event, entity, tags, player)
	-- debug_log(
	-- 	"n/t sdxn/dxn/mirroring: ",
	-- 	entity.name,
	-- 	entity.type,
	-- 	entity.supports_direction,
	-- 	entity.direction,
	-- 	entity.mirroring
	-- )

	if entity.type == "entity-ghost" then
		built_ghost(event, entity, tags, player)
	else
		built_real(event, entity, tags, player)
	end
end)

on_entity_cloned(function(event) debug_log("on_entity_cloned", event) end)

-- Death

on_unified_pre_destroy(function(event, entity, player)
	local un = entity.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
end)

on_unified_destroy(function(event, entity, player, leave_tombstone)
	local un = entity.unit_number
	if not un then return end
	local thing = get_thing_by_unit_number(un)
	if not thing then return end
	if leave_tombstone then
		-- thing:tombstone(entity)
		thing:destroy()
	else
		thing:destroy()
	end
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
