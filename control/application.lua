-- Code for blueprint application.

local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local world_state = require("lib.core.world-state")
local bp_bbox = require("lib.core.blueprint.bbox")
local bp_pos = require("lib.core.blueprint.pos")
local tlib = require("lib.core.table")
local event = require("lib.core.event")

local raise = require("control.events.typed").raise

local make_world_key = world_state.make_world_key
local get_world_key = world_state.get_world_key

local EMPTY = setmetatable({}, { __newindex = function() end })

-- Subtick handling
event.register_dynamic_handler(
	"application_subtick",
	---@param data things.Application
	function(_, data) data:on_subtick() end
)

---@class (exact) things.ApplicationOverlapEntry
---@field public thing things.Thing The Thing that was overlapped.
---@field public bp_entity BlueprintEntity The blueprint entity that overlapped it.
---@field public local_id int|nil The @i id in the blueprint, if any.

---@class (exact) things.Application
---@field public id int The unique application id.
---@field public player_index uint The player index who applied this.
---@field public tick_played uint The unpaused tick_played when this was applied.
---@field public bp Core.Blueprintish The blueprint being applied.
---@field public overlaps things.ApplicationOverlapEntry[] List of pre-existing entities that were overlapped by this application.
---@field public local_id_to_thing_id {[int]: int} Map of @i id in the blueprint to Thing id in the world.
---@field public world_key_to_local_id {[Core.WorldKey]: int} Map of world keys to @i id in the blueprint.
---@field public unresolved_edge_set {[things.NamedGraphEdge]: true} Set of local graph edges that could not be resolved because one or both Things were not known yet.
---@field public node_set {[int]: true} Set of Thing ids that are connected to edges.
local Application = class("things.Application")
_G.Application = Application

---@param player LuaPlayer
---@param bp Core.Blueprintish
---@param surface LuaSurface
---@param ev EventData.on_pre_build
---@return things.Application
function Application:new(player, bp, surface, ev)
	local id = counters.next("application")
	local obj = setmetatable({
		id = id,
		bp = bp,
		player_index = player.index,
		tick_played = game.ticks_played,
		overlaps = {},
		local_id_to_thing_id = {},
		unresolved_edge_set = {},
		node_set = {},
		world_key_to_local_id = {},
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
		ev.position,
		ev.direction,
		ev.flip_horizontal,
		ev.flip_vertical,
		snap_absolute and snap or nil,
		snap_offset,
		mod_settings.debug and surface or nil
	)

	-- Cataloguing and bookkeeping for entities
	local prebuild = get_prebuild_player_state(player.index)
	for index, bp_entity in pairs(entities) do
		local pos = entity_positions[index]
		if not pos then goto continue end
		local bp_entity_name = bp_entity.name
		local key = make_world_key(pos, surface.index, bp_entity_name)

		-- Mark as prebuilt
		prebuild:mark_key_as_prebuilt(key)

		-- Was the entity supposed to be a Thing?
		local local_id = (bp_entity.tags or EMPTY)["@i"]
		if not local_id then goto continue end
		---@cast local_id integer
		obj.world_key_to_local_id[key] = local_id

		-- Check for identical overlap
		local overlapped = surface.find_entities_filtered({
			position = pos,
		})
		tlib.filter_in_place(overlapped, function(e)
			if
				e.name == bp_entity_name
				or (e.type == "entity-ghost" and e.ghost_name == bp_entity_name)
			then
				return true
			else
				return false
			end
		end)
		overlapped = overlapped[1]
		if overlapped then
			local thing = get_thing_by_unit_number(overlapped.unit_number)
			if thing then
				table.insert(
					obj.overlaps,
					{ local_id = local_id, thing = thing, bp_entity = bp_entity }
				)
			end
		end

		-- Catalogue unresolved edges
		local edge_tags = (bp_entity.tags or EMPTY)["@edges"]
		if edge_tags then
			for graph_name, edges in pairs(edge_tags) do
				for to_local_id, edge_data in pairs(edges) do
					to_local_id = tonumber(to_local_id)
					if not to_local_id then
						debug_crash(
							"Application:new: invalid @edges tag in blueprint",
							bp_entity,
							graph_name
						)
					end
					---@cast to_local_id integer
					---@type things.NamedGraphEdge
					local edge
					if edge_data == true then
						edge = { first = local_id, second = to_local_id, name = graph_name }
					else
						edge = {
							first = local_id,
							second = to_local_id,
							data = edge_data,
							name = graph_name,
						}
					end
					obj.node_set[local_id] = true
					obj.node_set[to_local_id] = true
					obj.unresolved_edge_set[edge] = true
				end
			end
		end
		::continue::
	end

	-- Trigger subtick event. This is basically a virtual "on_blueprint_finished_building" event.
	event.dynamic_subtick_trigger("application_subtick", "subtick", obj)

	debug_log("Application:new: created application", obj)
	for k, v in pairs(obj.unresolved_edge_set) do
		debug_log("  unresolved edge:", k)
	end
	return obj
end

function Application:apply_overlapping_tags()
	for _, entry in ipairs(self.overlaps) do
		local thing = entry.thing
		local bp_entity = entry.bp_entity
		local new_tags = (bp_entity.tags or EMPTY)["@t"]
		if new_tags then
			thing:set_tags(new_tags --[[@as Tags]])
			debug_log(
				"Application:apply_overlapping_tags: applied tags to Thing",
				thing.id,
				thing.tags
			)
		end
	end
end

function Application:map_overlapping_local_ids()
	for _, entry in ipairs(self.overlaps) do
		if entry.local_id then
			self:map_local_id_to_thing_id(entry.local_id, entry.thing.id)
		end
	end
end

function Application:map_local_id_to_thing_id(local_id, thing_id)
	debug_log(
		"Application:map_local_id_to_thing_id: mapping local id",
		local_id,
		"to Thing",
		thing_id
	)
	self.local_id_to_thing_id[local_id] = thing_id
	self:resolve_graph_edges(local_id)
end

function Application:resolve_graph_edges(local_id)
	debug_log(
		"Application:resolve_graph_edges: resolving edges for local id",
		local_id,
		self.node_set,
		self.unresolved_edge_set
	)
	if not self.node_set[local_id] then return end
	local thing_id = self.local_id_to_thing_id[local_id]
	if not thing_id then return end
	local thing = get_thing(thing_id)
	if not thing then return end
	local unresolved_thing_edges = 0
	local resolved_thing_edges = 0
	for edge in pairs(self.unresolved_edge_set) do
		if edge.first ~= local_id and edge.second ~= local_id then goto continue end
		unresolved_thing_edges = unresolved_thing_edges + 1
		local other_local_id = (edge.first == local_id) and edge.second
			or edge.first
		local other_thing_id = self.local_id_to_thing_id[other_local_id]
		if not other_thing_id then goto continue end
		local other_thing = get_thing(other_thing_id)
		if other_thing then
			self.unresolved_edge_set[edge] = nil
			thing:graph_connect(edge.name, other_thing, edge.data)
			resolved_thing_edges = resolved_thing_edges + 1
			unresolved_thing_edges = unresolved_thing_edges - 1
			debug_log(
				"Application:resolve_graph_edges: connected",
				thing.id,
				other_thing.id,
				"on graph",
				edge.name
			)
		end
		::continue::
	end
end

function Application:on_subtick()
	-- TODO: impl
end

function Application:destroy() storage.applications[self.id] = nil end

function _G.garbage_collect_applications()
	local t = game.ticks_played
	for id, app in pairs(storage.applications) do
		if t > app.tick_played then
			debug_log("Garbage collecting application", id)
			app:destroy()
		end
	end
end

---Invoked when we receive the build event for a blueprinted Thing.
---Check active application states to see if any are waiting on this local id.
---@param local_id int
---@param world_key Core.WorldKey
---@param thing_id int
function _G.map_local_id_to_thing_id(local_id, world_key, thing_id)
	local t = game.ticks_played
	for _, app in pairs(storage.applications) do
		if
			t == app.tick_played
			and app.world_key_to_local_id[world_key] == local_id
		then
			app:map_local_id_to_thing_id(local_id, thing_id)
		end
	end
end
