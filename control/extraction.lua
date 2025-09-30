local class = require("lib.core.class").class
local counters = require("lib.core.counters")

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
_G.Extraction = Extraction

---@param bp Core.Blueprintish The blueprint being extracted.
---@param eid_to_world {[int]: LuaEntity} The mapping from bp to world entities. Comes from factorio api via `event.mapping`
function Extraction:new(bp, eid_to_world)
	local id = counters.next("extraction")
	local obj =
		setmetatable({ id = id, bp = bp, eid_to_world = eid_to_world }, self)
	storage.extractions[id] = obj
	return obj
end

---Map Things in the world into the blueprint. Must be called before any
---mutations are performed on the blueprint.
function Extraction:map_things()
	self.eid_to_thing = {}
	self.thing_id_to_eid = {}
	for eid, entity in pairs(self.eid_to_world) do
		if (not entity.valid) or not entity.unit_number then goto continue end
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then goto continue end
		self.eid_to_thing[eid] = thing
		self.thing_id_to_eid[thing.id] = eid
		self.bp.set_blueprint_entity_tag(eid, "@i", eid)
		self.bp.set_blueprint_entity_tag(eid, "@t", thing.tags)
		::continue::
	end
end

---Get entities from the blueprint.
function Extraction:map_entities()
	self.entities = self.bp.get_blueprint_entities() or {}
	self.next_entity_id = #self.entities + 1
end

---Map graph edges into the blueprint. Must be called after `map_things`.
function Extraction:map_edges()
	for eid, entity in pairs(self.eid_to_world) do
		if (not entity.valid) or not entity.unit_number then
			goto continue_entity
		end
		local thing = self.eid_to_thing[eid]
		if (not thing) or (not thing:has_edges()) then goto continue_entity end
		local edge_tags = {}
		for graph_name in pairs(thing.graph_set) do
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
			if next(edges_tags) then edge_tags[graph_name] = edges_tags end
		end
		if next(edge_tags) then
			self.bp.set_blueprint_entity_tag(eid, "@edges", edge_tags)
		end
		::continue_entity::
	end
end

function Extraction:destroy() storage.extractions[self.id] = nil end
