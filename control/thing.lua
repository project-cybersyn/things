local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local ws_lib = require("lib.core.world-state")
local entity_lib = require("lib.core.entities")

local get_world_key = ws_lib.get_world_key
local true_prototype_name = entity_lib.true_prototype_name

local EMPTY = setmetatable({}, { __newindex = function() end })

---@enum things.ThingManagementFlags
local ThingManagementFlags = {
	--- Force this entity to be destroyed when its parent is.
	DestroyWithParent = 1,
	--- Force this entity to die leaving a ghost when its parent does.
	DieWithParent = 2,
	--- When this entity is revived or built, also revive/build any children that are ghosts.
	ReviveChildren = 4,
	--- Force this entity to maintain its position relative to its parent when the parent is moved/rotated/flipped
	MaintainRelativePosition = 8,
	--- Force this entity to change its orientation relative to its parent when the parent is rotated/flipped
	MaintainRelativeOrientation = 16,
	--- This entity should be treated as immobile. (e.g. a picker dollies integration should ignore it)
	Immobile = 32,
	--- Force destroy the underlying entity if the Thing is destroyed.
	ForceDestroyEntity = 64,
}

---@enum things.ThingState
local ThingState = {
	---Thing is in an unknown state.
	unknown = "unknown",
	---Thing is a ghost that was manually thingified.
	ghost_initial = "ghost_initial",
	---Thing is ghost built from a blueprint.
	ghost_blueprint = "ghost_blueprint",
	---Thing is a ghost after its real entity died.
	ghost_died = "ghost_died",
	---Thing is a ghost that was determined to be from undo
	ghost_undo = "ghost_undo",
	---Thing is an alive entity that was manually thingified
	alive_initial = "alive_initial",
	---Thing was created alive from a blueprint (cheat mode)
	alive_blueprint = "alive_blueprint",
	---Thing was created alive from an undo operation (cheat mode)
	alive_undo = "alive_undo",
	---Thing was revived from a ghost
	alive_revived = "alive_revived",
	---Thing is destroyed but remaining as an undo tombstone.
	tombstone = "tombstone",
	---Thing has been destroyed and is no longer usable.
	destroyed = "destroyed",
}

---A `Thing` is the extended lifecycle of a collection of game entities that
---actually represent the same ultimate thing. For example, a thing could
---be constructed from a blueprint (entity #1: ghost), built by a bot (entity #2: real),
---killed by a biter and replaced by a ghost (entity #3: ghost),
---rebuilt by a player (entity #4: real), mined by a player (virtual entity
---in an undo buffer), then rebuilt by an undo command. (entity #5). All of
---these entities are different LuaEntity objects, but they all represent
---the same ultimate `Thing`
---@class (exact) things.Thing: StateMachine
---@field public id int Unique gamewide id for this Thing.
---@field public state things.Status|"uninitialized" Current lifecycle state of this Thing.
---@field public state_cause? things.StatusCause The cause of the last status change, if known.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public local_id? int If this Thing came from a blueprint, its local id within that blueprint.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, must be checked for validity each time used.
---@field public debug_overlay? Core.MultiLineTextOverlay Debug overlay for this Thing.
---@field public tags Tags The tags associated with this Thing.
---@field public last_known_position? MapPosition The last known position of this Thing's entity, if any.
---@field public n_undo_markers uint The number of undo markers currently associated with this Thing.
---@field public graph_set? {[string]: true} Set of graph names this Thing is a member of. If `nil`, the Thing is not a member of any graphs.
local Thing = class("things.Thing", StateMachine)
_G.Thing = Thing

---@return things.Thing
function Thing:new()
	local id = counters.next("entity")
	local obj = StateMachine.new(self, "uninitialized")
	obj.id = id
	obj.tags = {}
	obj.n_undo_markers = 0
	storage.things[id] = obj
	return obj
end

---Get the registered prototype name for this Thing.
function Thing:get_prototype_name()
	-- TODO: store and use actual registration data.
	if self.entity and self.entity.valid then
		return true_prototype_name(self.entity)
	end
	return nil
end

function Thing:undo_ref() self.n_undo_markers = self.n_undo_markers + 1 end

function Thing:undo_deref()
	self.n_undo_markers = math.max(0, self.n_undo_markers - 1)
	if self.n_undo_markers == 0 then
		-- TODO: cleanup
	end
end

---Update the `unit_number` associated with this Thing, maintaining referential
---integrity.
---@param unit_number uint?
function Thing:set_unit_number(unit_number)
	if self.unit_number == unit_number then return end
	storage.things_by_unit_number[self.unit_number or ""] = nil
	self.unit_number = unit_number
	if unit_number then storage.things_by_unit_number[unit_number] = self end
end

---Thing was built as a tagged ghost, likely from a BP.
---@param ghost LuaEntity A *valid* ghost.
---@param tags Tags The tags on the ghost.
---@param key Core.WorldKey The world key of the ghost.
function Thing:built_as_tagged_ghost(ghost, tags, key)
	if self.state ~= "uninitialized" then
		debug_crash(
			"Thing:built_as_tagged_ghost: unexpected state",
			self.id,
			self.state
		)
	end
	self.entity = ghost
	if tags["@t"] then
		self.tags = tags["@t"] --[[@as Tags]]
	end
	-- Tag ghost with Thing global ID.
	store_thing_ghost(key, self)
	self:set_unit_number(ghost.unit_number)
	self.state_cause = "blueprint"
	self:set_state("ghost")
	script.raise_event(
		"things-on_initialized",
		{ thing_id = self.id, entity = self.entity, status = self.state }
	)
end

---Thing was built as a tagged real entity, probably from a BP in cheat mode.
---@param entity LuaEntity A *valid* real entity.
---@param tags Tags The tags on the entity.
function Thing:built_as_tagged_real(entity, tags)
	if self.state ~= "uninitialized" then
		debug_crash(
			"Thing:built_as_tagged_real: unexpected state",
			self.id,
			self.state
		)
	end
	self.entity = entity
	if tags["@t"] then
		self.tags = tags["@t"] --[[@as Tags]]
	end
	self:set_unit_number(entity.unit_number)
	self.state_cause = "blueprint"
	self:set_state("real")
	script.raise_event(
		"things-on_initialized",
		{ thing_id = self.id, entity = self.entity, status = self.state }
	)
end

---Called when this Thing's entity dies, leaving a ghost behind.
---@param ghost LuaEntity
function Thing:died_leaving_ghost(ghost)
	-- Must be in alive state
	if self.state ~= "real" then
		debug_crash(
			"Thing:died_leaving_ghost: unexpected state",
			self.id,
			self.state
		)
	end
	self.entity = ghost
	self:set_unit_number(ghost.unit_number)
	store_thing_ghost(get_world_key(ghost), self)
	self.state_cause = "died"
	self:set_state("ghost")
end

---Called when this Thing is revived from a ghost.
---@param revived_entity LuaEntity
---@param tags Tags? The tags on the revived entity.
function Thing:revived_from_ghost(revived_entity, tags)
	if self.state ~= "ghost" then
		error(
			serpent.line(
				{ "Thing:revived_from_ghost: unexpected state", self.id, self.state },
				{ nocode = true }
			)
		)
	end
	self.entity = revived_entity
	self:set_unit_number(revived_entity.unit_number)
	self.state_cause = "revived"
	self:set_state("real")
end

---Try to resurrect a potentially tombstoned entity that was revived via
---an undo operation. `entity` is previously calculated by the undo
---subsystem to be a suitably overlapping entity.
---@param entity LuaEntity A *valid* entity.
---@param key Core.WorldKey The world key of the entity.
---@return boolean undoable `true` if entity matches a known tombstone.
function Thing:undo_with(entity, key)
	if self.state ~= "tombstone" then return false end
	self.entity = entity
	self:set_unit_number(entity.unit_number)
	self.state_cause = "undo"
	if entity.type == "entity-ghost" then
		store_thing_ghost(key, self)
		self:set_state("ghost")
	else
		self:set_state("real")
	end
	return true
end

function Thing:is_undo_ghost()
	-- TODO: evaluate if needed
end

---Invoked when the Thing's corresponding world entity is destroyed.
---Looks for a corresponding tombstone and either puts the Thing into
---tombstoned or destroyed state.
---@param entity LuaEntity
function Thing:entity_destroyed(entity)
	-- Expect `entity` to match our own opinion of what our entity is.
	-- TODO: remove after stability/edgecase verifications
	if (not self.entity) or not self.entity.valid or (self.entity ~= entity) then
		debug_crash(
			"Thing:entity_destroyed: thing's notion of its entity didn't match reality",
			self.id,
			self.entity,
			entity
		)
		return
	end
	self.last_known_position = entity.position
	self.entity = nil
	self:set_unit_number(nil)
	self.state_cause = "died"
	if self.n_undo_markers > 0 then
		self:set_state("tombstone")
	else
		self:destroy()
	end
end

---Destroy this Thing. This is a terminal state and the Thing may not be
---reused from here.
function Thing:destroy()
	if self.entity and self.entity.valid then
		self.last_known_position = self.entity.position
	end
	-- Disconnect graph edges
	self:graph_disconnect_all()
	-- TODO: force destroy entity if needed
	self.entity = nil
	-- Remove from registry
	storage.things_by_unit_number[self.unit_number or ""] = nil
	-- Give downstream a last bite at the apple
	self:set_state("destroyed")
	-- Remove from global registry
	storage.things[self.id] = nil
end

---@param tags Tags
function Thing:set_tags(tags)
	local previous_tags = self.tags
	self.tags = tags
	raise_thing_tags_changed(self, previous_tags)
	script.raise_event("things-on_tags_changed", {
		thing_id = self.id,
		previous_tags = previous_tags,
		new_tags = tags,
	})
end

---Create an edge from this Thing to another in the given Thing graph.
---@param graph_name string
---@param other things.Thing
---@param data? Tags Optional user data to associate with the edge.
---@return boolean created True if the edge was created, false if it already existed.
function Thing:graph_connect(graph_name, other, data)
	local graph = get_or_create_graph(graph_name)
	local created, edge = graph:add_edge(self.id, other.id)
	if created then
		if data then edge.data = data end
		if not self.graph_set then self.graph_set = {} end
		self.graph_set[graph_name] = true
		if not other.graph_set then other.graph_set = {} end
		other.graph_set[graph_name] = true
		script.raise_event("things-on_edges_changed", {
			graph_name = graph_name,
			change = "created",
			nodes = { [self.id] = true, [other.id] = true },
			edges = { edge },
		})
		return true
	end
	return false
end

---Remove an edge from this Thing to another in the given Thing graph.
---@param graph_name string
---@param other things.Thing
function Thing:graph_disconnect(graph_name, other)
	local graph = get_graph(graph_name)
	if not graph then return end
	local edge, isolated_1, isolated_2 = graph:remove_edge(self.id, other.id)
	if edge then
		if isolated_1 and self.graph_set then self.graph_set[graph_name] = nil end
		if isolated_2 and other.graph_set then other.graph_set[graph_name] = nil end
		script.raise_event("things-on_edges_changed", {
			graph_name = graph_name,
			change = "deleted",
			nodes = { [self.id] = true, [other.id] = true },
			edges = { edge },
		})
	end
end

---Remove this Thing from all graphs it is a member of.
function Thing:graph_disconnect_all()
	for graph_name in pairs(self.graph_set or EMPTY) do
		local graph = get_graph(graph_name)
		if not graph then goto continue end
		local edges = graph:get_edges(self.id)
		local node_set = { [self.id] = true }
		local edge_list = {}
		for other_id, edge in pairs(edges) do
			local other = get_thing(other_id)
			local edge_removed, isolated_1, isolated_2 =
				graph:remove_edge(self.id, other_id)
			if isolated_2 and other and other.graph_set then
				other.graph_set[graph_name] = nil
			end
			table.insert(edge_list, edge)
			node_set[other_id] = true
		end
		self.graph_set[graph_name] = nil
		script.raise_event("things-on_edges_changed", {
			graph_name = graph_name,
			change = "deleted",
			nodes = node_set,
			edges = edge_list,
		})
		::continue::
	end
end

---Check for an edge in the given Thing graph.
---@param graph_name string
---@param other things.Thing
function Thing:graph_get_edge(graph_name, other)
	local graph = get_graph(graph_name)
	if not graph then return nil end
	return graph:get_edge(self.id, other.id)
end

---Get all edges in the given Thing graph that this Thing is a member of.
---@param graph_name string
---@return {[int]: things.GraphEdge}
function Thing:graph_get_edges(graph_name)
	local graph = get_graph(graph_name)
	if not graph then return EMPTY end
	return graph:get_edges(self.id)
end

---Determine if this Thing has any edges in any graph.
function Thing:has_edges() return self.graph_set and next(self.graph_set) ~= nil end

function Thing:on_changed_state(new_state, old_state)
	raise_thing_status(self, new_state, old_state --[[@as string]])
	script.raise_event("things-on_status_changed", {
		thing_id = self.id,
		entity = self.entity,
		new_status = new_state,
		old_status = old_state,
		cause = self.state_cause,
	})
	-- Create on_edges_changed events
	-- For destroyed Things, skip the status_changed event in favor of the
	-- delete event.
	if new_state == "destroyed" then return end
	for graph_name in pairs(self.graph_set or EMPTY) do
		local graph = get_graph(graph_name)
		if not graph then goto continue end
		local edges = graph:get_edges(self.id)
		local edge_list = {}
		local node_set = {}
		node_set[self.id] = true
		for other_id, edge in pairs(edges) do
			table.insert(edge_list, edge)
			node_set[other_id] = true
		end
		script.raise_event("things-on_edges_changed", {
			graph_name = graph_name,
			change = "status_changed",
			nodes = node_set,
			edges = edge_list,
		})
		::continue::
	end
end

---Get a Thing by its thing_id.
---@param id uint?
---@return things.Thing?
function _G.get_thing(id) return storage.things[id or ""] end

---@param unit_number uint?
---@return things.Thing?
function _G.get_thing_by_unit_number(unit_number)
	return storage.things_by_unit_number[unit_number or ""]
end

---@param entity LuaEntity A *valid* LuaEntity with a `unit_number`
---@param key Core.WorldKey The world key of the entity.
---@return boolean was_created True if a new Thing was created, false if the entity was already a Thing.
---@return things.Thing?
function _G.thingify_entity(entity, key)
	local thing = get_thing_by_unit_number(entity.unit_number)
	if thing then return false, thing end
	thing = Thing:new()
	thing.entity = entity
	thing:set_unit_number(entity.unit_number)
	thing.state_cause = "created"
	if entity.type == "entity-ghost" then
		store_thing_ghost(key, thing)
		thing:set_state("ghost")
	else
		thing:set_state("real")
	end
	script.raise_event(
		"things-on_initialized",
		{ thing_id = thing.id, entity = thing.entity, status = thing.state }
	)
	return true, thing
end

---Mark a Thing ghost in the world by world key.
---@param key Core.WorldKey
---@param thing things.Thing
function _G.store_thing_ghost(key, thing)
	local tg = storage.thing_ghosts
	if tg[key] then
		local previous_thing = get_thing(tg[key])
		local pt_id = previous_thing and previous_thing.id or "UNKNOWN"
		local pt_entity_name = (
			previous_thing and previous_thing:get_prototype_name()
		) or "UNKNOWN"
		game.print({
			"things-messages.duplicate-ghost-warning",
			key,
			pt_id,
			pt_entity_name,
			thing.id,
			thing:get_prototype_name() or "UNKNOWN",
		})
	end
	tg[key] = thing.id
end

---Removed a marked Thing ghost from storage.
---@param key Core.WorldKey
function _G.clear_thing_ghost(key) storage.thing_ghosts[key] = nil end
