local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local constants = require("control.constants")
local EMPTY = require("lib.core.table").EMPTY_STRICT

local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local TAGS_TAG = constants.TAGS_TAG
local CHILDREN_TAG = constants.CHILDREN_TAG
local PARENT_TAG = constants.PARENT_TAG
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local BLUEPRINT_TAG_SET = constants.BLUEPRINT_TAG_SET

local lib = {}

---State of a blueprint being extracted from the world.
---@class (exact) things.Extraction
---@field public id int The unique extraction id.
---@field public bp Core.Blueprintish The blueprint being extracted.
---@field public entities {[int]: BlueprintEntity} Entities in the blueprint. Note that deletions may make this sparse.
---@field public next_entity_id int The next entity id to use for a new entity in this extraction.
---@field public eid_to_world {[int]: LuaEntity} Map of entity id in the blueprint to corresponding world entity.
---@field public eid_to_thing {[int]: things.Thing} Map of entity id in the blueprint to known Thing in the world.
---@field public thing_id_to_eid {[int]: int} Map of known Thing id to entity id in the blueprint.
local Extraction = class("things.Extraction")
lib.Extraction = Extraction

---@param bp Core.Blueprintish The blueprint being extracted.
---@param eid_to_world {[int]: LuaEntity} The mapping from bp to world entities. Comes from factorio api via `event.mapping`
---@return things.Extraction|nil #The extraction manager object, or nil if there were no Things in the blueprint.
function Extraction:new(bp, eid_to_world)
	-- Filter for Things
	local eid_to_thing = {}
	local thing_id_to_eid = {}
	for eid, entity in pairs(eid_to_world) do
		if (not entity.valid) or not entity.unit_number then goto continue end
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then goto continue end
		eid_to_thing[eid] = thing
		thing_id_to_eid[thing.id] = eid
		::continue::
	end

	if not next(eid_to_thing) then
		debug_log("Extraction:new(): no Things in blueprint.")
		return nil
	end

	local id = counters.next("extraction")
	local obj = setmetatable({
		id = id,
		bp = bp,
		eid_to_world = eid_to_world,
		eid_to_thing = eid_to_thing,
		thing_id_to_eid = thing_id_to_eid,
	}, self) --[[@as things.Extraction]]
	storage.extractions[id] = obj

	obj:init_normalize_thing_tags()
	obj:init_map_parent_child()
	obj:init_map_edges()
	obj:init_map_entities()

	return obj
end

---Ensure all Things in the blueprint have proper base tags.
function Extraction:init_normalize_thing_tags()
	for eid, thing in pairs(self.eid_to_thing) do
		-- Normalize by clearing all tags including possible residual tags from
		-- previous blueprint ghosts.
		for tag in pairs(BLUEPRINT_TAG_SET) do
			self.bp.set_blueprint_entity_tag(eid, tag, nil)
		end
		-- Apply basic tags.
		self.bp.set_blueprint_entity_tag(eid, LOCAL_ID_TAG, eid)
		if thing.tags and next(thing.tags) then
			self.bp.set_blueprint_entity_tag(eid, TAGS_TAG, thing.tags)
		end
	end
end

---Get entities from the blueprint.
---This is called last so as to pick up all tag changes made by other init_*
---methods.
function Extraction:init_map_entities()
	self.entities = self.bp.get_blueprint_entities() or {}
	self.next_entity_id = #self.entities + 1
end

---Map graph edges into the blueprint.
---Must be called after `init_normalize_thing_tags`.
function Extraction:init_map_edges()
	for eid, thing in pairs(self.eid_to_thing) do
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
				-- Only add edge for which we are the lower id, to avoid duplicates.
				if thing.id ~= edge.first then goto continue_edge end
				local local_to = self.thing_id_to_eid[to]
				if local_to then
					edges_tags[local_to] = edge.data and edge.data or true
				end
				::continue_edge::
			end
			if next(edges_tags) then
				edge_tags = edge_tags or {}
				edge_tags[graph_name] = edges_tags
			end
		end
		if edge_tags and next(edge_tags) then
			self.bp.set_blueprint_entity_tag(eid, GRAPH_EDGES_TAG, edge_tags)
		end
	end
end

---Map parent-child relationships into the blueprint.
---Must be called after `init_normalize_thing_tags`.
function Extraction:init_map_parent_child()
	for eid, thing in pairs(self.eid_to_thing) do
		local parent = thing.parent
		if parent then
			local parent_eid = self.thing_id_to_eid[parent.id]
			if parent_eid then
				self.bp.set_blueprint_entity_tag(
					eid,
					PARENT_TAG,
					{ thing.child_key_in_parent, parent_eid }
				)
			end
		end
	end
end

function Extraction:finish()
	-- TODO: atomic blueprint operations; cleanup and rewrite BP here if needed.
	self:destroy()
end

function Extraction:destroy() storage.extractions[self.id] = nil end

return lib
