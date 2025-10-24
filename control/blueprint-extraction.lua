local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local constants = require("control.constants")
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")

local EMPTY = tlib.EMPTY_STRICT
local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local NAME_TAG = constants.NAME_TAG
local TAGS_TAG = constants.TAGS_TAG
local PARENT_TAG = constants.PARENT_TAG
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local BLUEPRINT_TAG_SET = constants.BLUEPRINT_TAG_SET
local ORIENTATION_TAG = constants.ORIENTATION_TAG

local lib = {}

---State of a blueprint being extracted from the world.
---@class (exact) things.Extraction
---@field public id int The unique extraction id.
---@field public bp Core.Blueprintish The blueprint being extracted.
---@field public by_index {[int]: things.ExtractedEntity} Mapping from blueprint entity index to internal info.
---@field public by_thing_id {[int64]: things.ExtractedEntity} Mapping from Thing id to internal info.
---@field public next_index int The next available blueprint entity index.
---@field public has_things boolean True if the blueprint has any Things.
local Extraction = class("things.Extraction")
lib.Extraction = Extraction

---@type things.Extraction|nil
lib.running_extraction = nil

---@param bp Core.Blueprintish The blueprint being extracted.
---@param index_to_world {[int]: LuaEntity} The mapping from bp indices to world entities. Comes from factorio api via `event.mapping`
---@return things.Extraction #The extraction manager object, or nil if there were no Things in the blueprint.
function Extraction:new(bp, index_to_world)
	local id = counters.next("extraction")
	local obj = setmetatable({
		id = id,
		bp = bp,
		by_index = {},
		by_thing_id = {},
		has_things = false,
	}, self) --[[@as things.Extraction]]

	local by_index = obj.by_index
	local by_thing_id = obj.by_thing_id
	for index, entity in pairs(index_to_world) do
		local ex_e = {
			index = index,
			entity = entity,
		}
		by_index[index] = ex_e
		if not entity.unit_number then goto continue end
		local thing = get_thing_by_unit_number(entity.unit_number)
		if thing then
			ex_e.thing_id = thing.id
			by_thing_id[thing.id] = ex_e
			strace.debug(
				"Extraction:new(): found Thing",
				thing.id,
				"for blueprint entity index",
				index
			)
		end

		::continue::
	end

	if next(by_thing_id) then
		strace.debug(
			"Extraction:new():",
			table_size(by_thing_id),
			"Things in blueprint."
		)
		self.has_things = true
	else
		debug_log("Extraction:new(): no Things in blueprint.")
	end

	obj:init_normalize_thing_tags()
	-- obj:init_map_parent_child()
	-- obj:init_map_edges()
	obj:init_map_entities()

	lib.running_extraction = obj
	return obj
end

---Ensure all Things in the blueprint have proper base tags.
function Extraction:init_normalize_thing_tags()
	for _, info in pairs(self.by_thing_id) do
		local index = info.index
		-- We know this is not nil from above.
		local thing = get_thing_by_id(info.thing_id) --[[@as things.Thing]]
		-- Normalize by clearing all tags including possible residual tags from
		-- previous blueprint ghosts.
		for tag in pairs(BLUEPRINT_TAG_SET) do
			self.bp.set_blueprint_entity_tag(index, tag, nil)
		end
		-- Apply basic tags.
		self.bp.set_blueprint_entity_tag(index, NAME_TAG, thing.name)
		self.bp.set_blueprint_entity_tag(index, LOCAL_ID_TAG, index)
		if thing.tags and next(thing.tags) then
			self.bp.set_blueprint_entity_tag(index, TAGS_TAG, thing.tags)
		end
		if thing.virtual_orientation then
			self.bp.set_blueprint_entity_tag(
				index,
				ORIENTATION_TAG,
				thing.virtual_orientation
			)
		end
	end
end

---Get entities from the blueprint.
---This is called last so as to pick up all tag changes made by other init_*
---methods.
function Extraction:init_map_entities()
	local entities = self.bp.get_blueprint_entities() or {}
	for index, info in pairs(self.by_index) do
		info.bp_entity = entities[index]
	end
	self.next_index = #entities + 1
end

---Map graph edges into the blueprint.
---Must be called after `init_normalize_thing_tags`.
function Extraction:init_map_edges()
	for index, thing in pairs(self.index_to_thing) do
		local edge_tags = nil
		for graph_name in pairs(thing.graph_set or EMPTY) do
			local edges = thing:graph_get_edges(graph_name)
			local edges_tags = {}
			debug_log(
				"Extraction:map_edges: mapping edges for Thing",
				thing.id,
				edges
			)
			for to, edge in pairs(edges) do
				local local_to = self.thing_id_to_index[to]
				if local_to then
					edges_tags[local_to] = edge.data and edge.data or true
				end
			end
			if next(edges_tags) then
				edge_tags = edge_tags or {}
				edge_tags[graph_name] = edges_tags
			end
		end
		if edge_tags and next(edge_tags) then
			self.bp.set_blueprint_entity_tag(index, GRAPH_EDGES_TAG, edge_tags)
		end
	end
end

---Map parent-child relationships into the blueprint.
---Must be called after `init_normalize_thing_tags`.
function Extraction:init_map_parent_child()
	for index, thing in pairs(self.index_to_thing) do
		local parent = thing.parent
		if parent then
			local parent_eid = self.thing_id_to_index[parent[1]]
			if parent_eid then
				self.bp.set_blueprint_entity_tag(
					index,
					PARENT_TAG,
					{ parent[2], parent_eid }
				)
			end
		end
	end
end

function Extraction:finish()
	-- TODO: atomic blueprint operations; cleanup and rewrite BP here if needed.
	self:destroy()
end

function Extraction:destroy() lib.running_extraction = nil end

return lib
