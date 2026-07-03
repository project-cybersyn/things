--------------------------------------------------------------------------------
-- BP EXTRACTION
--------------------------------------------------------------------------------

local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local constants = require("control.constants")
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local graph_lib = require("control.graph")
local events = require("lib.core.event")
local md_lib = require("lib.core.metadata")

local EMPTY = tlib.EMPTY_STRICT
local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local NAME_TAG = constants.NAME_TAG
local TAGS_TAG = constants.TAGS_TAG
local PARENT_TAG = constants.PARENT_TAG
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local BLUEPRINT_TAG_SET = constants.BLUEPRINT_TAG_SET
local ORIENTATION_TAG = constants.ORIENTATION_TAG

local lib = {}

---Entity within a blueprint being extracted.
---@class (exact) things.ExtractedEntity
---@field public index int The index of the entity within the extraction process.
---@field public bp_entity BlueprintEntity The blueprint entity data.
---@field public entity? LuaEntity The in-world entity this blueprint entity represents.
---@field public thing_id things.Id? The Thing this blueprint entity represents.

---State of a blueprint being extracted from the world.
---@class (exact) things.Extraction
---@field public id int The unique extraction id.
---@field public bp Core.Blueprintish The blueprint being extracted.
---@field public by_index {[int]: things.ExtractedEntity} Mapping from blueprint entity index to internal info.
---@field public by_thing_id {[int64]: things.ExtractedEntity} Mapping from Thing id to internal info.
---@field public index_to_world {[uint]: LuaEntity} The mapping from blueprint entity index to world entity. Comes from factorio api via `event.mapping`.
---@field public has_things true? True if the blueprint has any Things.
---@field public is_edited true? True if the blueprint was edited during extraction and thus needs to be re-written with `set_blueprint_entities`.
---@field public profiler LuaProfiler A profiler for measuring time spent in extraction and editing.
local Extraction = class("things.Extraction")
lib.Extraction = Extraction

---@param bp Core.Blueprintish The blueprint being extracted.
---@param index_to_world table<uint32, LuaEntity> The mapping from bp indices to world entities. Comes from factorio api via `event.mapping`
---@return things.Extraction #The extraction manager object, or nil if there were no Things in the blueprint.
function Extraction:new(bp, index_to_world)
	local id = counters.next("extraction")
	local obj = setmetatable({
		id = id,
		bp = bp,
		by_index = {},
		by_thing_id = {},
		profiler = helpers.create_profiler(),
		index_to_world = index_to_world,
	}, self) --[[@as things.Extraction]]

	return obj
end

function Extraction:extract()
	self:enum_entities()
	self:map_things()
	self:normalize_thing_tags()
	self:map_parent_child()
	self:map_edges()
end

function Extraction:enum_entities()
	local bp_entities = self.bp.get_blueprint_entities() or {}
	local by_index = self.by_index
	local index_to_world = self.index_to_world
	for index, bp_entity in pairs(bp_entities) do
		by_index[index] = {
			index = index,
			bp_entity = bp_entity,
			entity = index_to_world[index],
		}
	end
end

function Extraction:map_things()
	local by_thing_id = self.by_thing_id

	for index, info in pairs(self.by_index) do
		local entity = info.entity
		if not entity or not entity.valid then goto continue end
		local thing = get_thing_by_unit_number(entity.unit_number)
		if thing then
			info.thing_id = thing.id
			by_thing_id[thing.id] = info
			strace.debug(
				"Extraction:map_things(): mapped Thing",
				thing.id,
				"to blueprint entity index",
				index
			)
		end
		::continue::
	end

	if next(by_thing_id) then
		strace.debug(
			"Extraction:map_things():",
			table_size(by_thing_id),
			"Things in blueprint."
		)
		self.has_things = true
	else
		strace.debug("Extraction:map_things(): no Things in blueprint.")
	end
end

---Ensure all Things in the blueprint have proper base tags.
function Extraction:normalize_thing_tags()
	for _, info in pairs(self.by_thing_id) do
		local index = info.index
		-- We know this is not nil from above.
		local thing = get_thing_by_id(info.thing_id) --[[@as things.Thing]]

		local tags = self.bp.get_blueprint_entity_tags(index)
		-- Normalize by clearing all tags including possible residual tags from
		-- previous blueprint ghosts.
		for tag in pairs(BLUEPRINT_TAG_SET) do
			tags[tag] = nil
		end
		-- Apply basic tags.
		tags[NAME_TAG] = thing.name
		tags[LOCAL_ID_TAG] = index
		if thing.tags and next(thing.tags) then tags[TAGS_TAG] = thing.tags end
		if thing.virtual_orientation then
			tags[ORIENTATION_TAG] = thing.virtual_orientation
		end

		self.bp.set_blueprint_entity_tags(index, tags)
	end
end

---Map graph edges into the blueprint.
---Must be called after `normalize_thing_tags`.
function Extraction:map_edges()
	for thing_id, info in pairs(self.by_thing_id) do
		local edge_tags = nil
		local graphs = graph_lib.get_graphs_containing_node(thing_id)
		for graph_name, graph in pairs(graphs) do
			local out_edges = graph:get_edges(thing_id)
			local edges_tags = {}
			strace.debug(
				"Extraction:map_edges: mapping edges for Thing",
				thing_id,
				out_edges
			)
			for to_thing_id, edge in pairs(out_edges) do
				local to_info = self.by_thing_id[to_thing_id]
				if to_info then
					edges_tags[to_info.index] = edge.data and edge.data or true
				end
			end
			if next(edges_tags) then
				edge_tags = edge_tags or {}
				edge_tags[graph_name] = edges_tags
			end
		end
		if edge_tags and next(edge_tags) then
			self.bp.set_blueprint_entity_tag(info.index, GRAPH_EDGES_TAG, edge_tags)
		end
	end
end

---Map parent-child relationships into the blueprint.
---Must be called after `normalize_thing_tags`.
function Extraction:map_parent_child()
	for thing_id, info in pairs(self.by_thing_id) do
		local thing = get_thing_by_id(thing_id)
		if not thing then goto continue end
		local parent_relationship = thing.parent
		if parent_relationship then
			local parent_info = self.by_thing_id[parent_relationship[1]]
			if parent_info then
				self.bp.set_blueprint_entity_tag(info.index, PARENT_TAG, {
					parent_info.index,
					parent_relationship[2],
					parent_relationship[3],
					parent_relationship[4],
				})
			end
		end
		::continue::
	end
end

--------------------------------------------------------------------------------
-- EXTERNAL INTERFACE
--------------------------------------------------------------------------------

---@param bp Core.Blueprintish
---@param bp_to_world table<uint32, LuaEntity> Mapping from blueprint entity index to world entity.
function lib.extract_blueprint(bp, bp_to_world)
	strace.debug("*** Extract blueprint")
	local extraction = Extraction:new(bp, bp_to_world)
	extraction:extract()
	strace.debug("*** Extract blueprint: finished")
end

return lib
