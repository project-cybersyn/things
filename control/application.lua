-- Code for blueprint application.

local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local world_state = require("lib.core.world-state")
local bp_bbox = require("lib.core.blueprint.bbox")
local bp_pos = require("lib.core.blueprint.pos")

local make_world_key = world_state.make_world_key
local get_world_key = world_state.get_world_key

local EMPTY = setmetatable({}, { __newindex = function() end })

---@class (exact) things.ApplicationOverlapEntry
---@field public thing things.Thing The Thing that was overlapped.
---@field public bp_entity BlueprintEntity The blueprint entity that overlapped it.

---@class (exact) things.Application
---@field public id int The unique application id.
---@field public player_index uint The player index who applied this.
---@field public tick_played uint The unpaused tick_played when this was applied.
---@field public bp Core.Blueprintish The blueprint being applied.
---@field public overlaps things.ApplicationOverlapEntry[] List of pre-existing entities that were overlapped by this application.
local Application = class("things.Application")
_G.Application = Application

---@param player LuaPlayer
---@param bp Core.Blueprintish
---@param surface LuaSurface
---@param event EventData.on_pre_build
---@return things.Application
function Application:new(player, bp, surface, event)
	local id = counters.next("application")
	local obj = setmetatable({
		id = id,
		bp = bp,
		player_index = player.index,
		tick_played = game.ticks_played,
		overlaps = {},
	}, self)
	storage.applications[id] = obj

	-- Get entities.
	local entities = bp.get_blueprint_entities()
	if (not entities) or (#entities == 0) then
		debug_log("on_blueprint_apply: no entities")
		return obj
	end
	local snap = bp.blueprint_snap_to_grid
	local snap_offset = bp.blueprint_position_relative_to_grid
	local snap_absolute = bp.blueprint_absolute_snapping
	local bbox, snap_index = bp_bbox.get_blueprint_bbox(entities)
	local entity_positions = bp_pos.get_blueprint_world_positions(
		entities,
		nil,
		bbox,
		snap_index,
		event.position,
		event.direction,
		event.flip_horizontal,
		event.flip_vertical,
		snap_absolute and snap or nil,
		snap_offset,
		mod_settings.debug and surface or nil
	)

	-- Cataloguing and bookkeeping for entities
	local prebuild = get_prebuild_player_state(player.index)
	for index, bp_entity in pairs(entities) do
		local pos = entity_positions[index]
		if not pos then goto continue end
		local key = make_world_key(pos, surface.index, bp_entity.name)

		-- Mark as prebuilt
		prebuild:mark_key_as_prebuilt(key)

		-- Was the entity supposed to be a Thing?
		local local_id = (bp_entity.tags or EMPTY)["@i"]
		if not local_id then goto continue end

		-- Check for identical overlap
		-- (`find_entities_filtered` here allows all qualities to overlap. open
		-- question if this is correct behavior.)
		local overlapping = surface.find_entities_filtered({
			name = bp_entity.name,
			position = pos,
		})[1]
		if overlapping then
			local thing = get_thing_by_unit_number(overlapping.unit_number)
			if thing then
				table.insert(obj.overlaps, { thing = thing, bp_entity = bp_entity })
			end
		end
		::continue::
	end

	return obj
end

function Application:apply_overlapping_tags()
	for _, entry in ipairs(self.overlaps) do
		local thing = entry.thing
		local bp_entity = entry.bp_entity
		local new_tags = (bp_entity.tags or EMPTY)["@t"]
		if new_tags then
			thing:set_tags(new_tags)
			debug_log(
				"Application:apply_overlapping_tags: applied tags to Thing",
				thing.id,
				thing.tags
			)
		end
	end
end

function Application:destroy() storage.applications[self.id] = nil end
