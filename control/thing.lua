local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local ws_lib = require("lib.core.world-state")
local entity_lib = require("lib.core.entities")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local oclass_lib = require("lib.core.orientation.orientation-class")

local TAGS_TAG = constants.TAGS_TAG
local ORIENTATION_TAG = constants.ORIENTATION_TAG
local WORLD_ORIENTATION = oclass_lib.OrientationContext.World
local OC_048CM_RF = oclass_lib.OrientationClass.OC_048CM_RF

local raise = require("control.events.typed").raise

local get_world_key = ws_lib.get_world_key
local true_prototype_name = entity_lib.true_prototype_name

local EMPTY = tlib.EMPTY_STRICT
local NO_RAISE_DESTROY = { raise_destroy = false }

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
---@field public state things.Status Current lifecycle state of this Thing.
---@field public registration? things.ThingRegistration The registration data for this Thing's prototype, if any.
---@field public virtual_orientation? Core.Orientation If this class of Thing has virtual orientation, this is its current virtual orientation. This field is read-only.
---@field public is_silent? boolean If true, suppress events for this Thing.
---@field public state_cause? things.StatusCause The cause of the last status change, if known.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public local_id? int If this Thing came from a blueprint, its local id within that blueprint.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, must be checked for validity each time used.
---@field public key Core.WorldKey? The world key of this Thing's entity, if any. Only valid to the extent `entity` exists and is valid.
---@field public debug_overlay? Core.MultiLineTextOverlay Debug overlay for this Thing.
---@field public tags Tags The tags associated with this Thing.
---@field public last_known_position? MapPosition The last known position of this Thing's entity, if any.
---@field public n_undo_markers uint The number of undo markers currently associated with this Thing.
---@field public graph_set? {[string]: true} Set of graph names this Thing is a member of. If `nil`, the Thing is not a member of any graphs.
---@field public parent? things.Thing Parent of this Thing, if any.
---@field public child_key_in_parent? int|string The key this Thing is registered under in its parent's `children` map, if any.
---@field public children? {[int|string]: things.Thing} Map from child names (which may be numbers or strings) to child Things.
---@field public transient_data? Tags Custom transient data associated with this Thing. This will NOT be blueprinted.
local Thing = class("things.Thing", StateMachine)
_G.Thing = Thing

---Construct an uninitialized Thing.
---@return things.Thing
function Thing:new()
	local id = counters.next("thing")
	local obj = StateMachine.new(self, "void")
	obj.id = id
	obj.tags = {}
	obj.n_undo_markers = 0
	storage.things[id] = obj
	return obj
end

---Construct a Thing corresponding to a construction operation.
---@param op things.Operation
function Thing:new_from_operation(op)
	local obj = Thing.new(self)
	obj:set_entity(op.entity, op.key)
	if op.tags and op.tags[TAGS_TAG] then
		obj.tags = op.tags[TAGS_TAG] --[[@as Tags]]
	end
	return obj
end

---Summarizes a Thing for remote interface output.
---@return things.ThingSummary
function Thing:summarize()
	return {
		id = self.id,
		entity = self.entity,
		status = self.state,
		virtual_orientation = self.virtual_orientation
			and self.virtual_orientation:to_data(),
		tags = self.tags,
		graph_set = self.graph_set,
		parent_id = self.parent and self.parent.id,
		child_key_in_parent = self.child_key_in_parent,
	}
end

---@param unit_number uint?
local function internal_set_unit_number(self, unit_number)
	if self.unit_number == unit_number then return end
	storage.things_by_unit_number[self.unit_number or ""] = nil
	self.unit_number = unit_number
	if unit_number then storage.things_by_unit_number[unit_number] = self end
end

---@param entity LuaEntity?
---@param key Core.WorldKey?
function Thing:set_entity(entity, key)
	if entity and self.state == "destroyed" then
		debug_crash(
			"Thing:set_entity: cannot set entity on destroyed Thing",
			self.id,
			entity,
			key
		)
	end
	if entity == self.entity then return end
	if not entity or not entity.valid then
		self.entity = nil
		self.key = nil
		internal_set_unit_number(self, nil)
		return
	end
	self.entity = entity
	self.key = key
	local unit_number = entity.unit_number
	internal_set_unit_number(self, unit_number)
	if entity.type == "entity-ghost" then
		store_thing_ghost(key --[[@as Core.WorldKey]], self)
	end
end

function Thing:apply_status()
	if self.entity and self.entity.valid then
		if self.entity.type == "entity-ghost" then
			self:set_state("ghost")
		else
			self:set_state("real")
		end
	end
end

function Thing:initialize() raise("thing_initialized", self) end

---Get the registered prototype name for this Thing.
function Thing:get_prototype_name()
	-- TODO: store and use actual registration data.
	if self.entity and self.entity.valid then
		return true_prototype_name(self.entity)
	end
	return nil
end

---Update a Thing's internal registration state. Should only be called in
---code that is beginning a Thing's lifecycle.
function Thing:update_registration()
	self.registration = get_thing_registration(self:get_prototype_name())
	if not self.registration then
		debug_crash(
			"Thing:update_registration: no Thing registration for thing id and entity",
			self.id,
			self.entity
		)
	end
end

---Get the custom event prototype name for a given Things event name, if any.
---@param thing_event_name things.EventName
---@return string|nil
function Thing:get_custom_event_name(thing_event_name)
	return ((self.registration and self.registration.custom_events) or EMPTY)[thing_event_name]
end

function Thing:undo_ref() self.n_undo_markers = self.n_undo_markers + 1 end

function Thing:undo_deref()
	self.n_undo_markers = math.max(0, self.n_undo_markers - 1)
	if self.n_undo_markers == 0 then
		-- TODO: cleanup
	end
end

---@return boolean
function Thing:is_tombstone() return self.state == "tombstone" end

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
	self:set_entity(ghost, get_world_key(ghost))
	self.state_cause = "destroyed"
	self:set_state("ghost")
end

---Called when this Thing is revived from a ghost.
---@param revived_entity LuaEntity
---@param key Core.WorldKey
function Thing:revived_from_ghost(revived_entity, key)
	if self.state ~= "ghost" then
		debug_crash(
			"Thing:revived_from_ghost: unexpected state",
			self.id,
			self.state
		)
	end
	self:set_entity(revived_entity, key)
	self.state_cause = "revived"
	self:set_state("real")
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
	-- If I am a child, void me.
	if self.parent then return self:void(true) end
	-- If not a child, tombstone or destroy as appropriate.
	self.last_known_position = entity.position
	self:set_entity(nil, nil)
	self.state_cause = "destroyed"
	if self.n_undo_markers > 0 then
		self:set_state("tombstone")
	else
		self:destroy(false, true)
	end
end

---Destroy this Thing. This is a terminal state and the Thing may not be
---reused from here.
---@param skip_deparent boolean?
---@param skip_destroy boolean? If true, do not destroy the underlying entity.
function Thing:destroy(skip_deparent, skip_destroy)
	if self.entity and self.entity.valid then
		self.last_known_position = self.entity.position
	end
	-- Disconnect graph edges
	self:graph_disconnect_all()
	-- Remove from parent
	if self.parent and not skip_deparent then
		self.parent:remove_children(self)
	end
	-- Destroy children
	for _, child in pairs(self.children or EMPTY) do
		child:destroy(true)
	end
	-- Give downstream a last bite at the apple
	self:set_state("destroyed")
	local former_entity = self.entity
	self:set_entity(nil, nil)
	-- Remove from global registry
	storage.things[self.id] = nil
	-- Destroy underlying entity if needed
	if not skip_destroy then
		if former_entity and former_entity.valid then
			former_entity.destroy(NO_RAISE_DESTROY)
		end
	end
end

---Void this Thing. This removes its associated entity without destroying
---its internal state or relationships. Voiding is a non-terminal state and
---an entity may be later reattached.
---@param skip_destroy boolean? If true, do not destroy the underlying entity.
function Thing:void(skip_destroy)
	if self.entity and self.entity.valid then
		self.last_known_position = self.entity.position
	end
	for _, child in pairs(self.children or EMPTY) do
		child:void()
	end
	self:set_state("void")
	local former_entity = self.entity
	self:set_entity(nil, nil)
	if not skip_destroy then
		if former_entity and former_entity.valid then
			former_entity.destroy(NO_RAISE_DESTROY)
		end
	end
end

---Devoid this Thing by attaching it to the given real or ghost entity.
---@param entity LuaEntity A *valid* entity.
---@param key? Core.WorldKey
---@return boolean devoided True if the Thing was devoided, false if not. Always false if the Thing was not in `void` state.
function Thing:devoid(entity, key)
	if self.state ~= "void" then return false end
	self:set_entity(entity, key or get_world_key(entity))
	self:apply_status()
	return true
end

---@param tags Tags
function Thing:set_tags(tags)
	local previous_tags = self.tags
	self.tags = tags
	if not self.is_silent then
		raise("thing_tags_changed", self, previous_tags)
	end
end

---@param tag string
---@param value AnyBasic
function Thing:set_tag(tag, value)
	self.tags[tag] = value
	if not self.is_silent then
		raise("thing_tags_changed", self, { [tag] = value })
	end
end

---Set custom transient data on this Thing.
---@param key string
---@param value AnyBasic?
function Thing:set_transient_data(key, value)
	if value and not self.transient_data then self.transient_data = {} end
	self.transient_data[key] = value
	if self.transient_data and not next(self.transient_data) then
		self.transient_data = nil
	end
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
		raise(
			"thing_edges_changed",
			self,
			graph_name,
			"created",
			{ [self.id] = true, [other.id] = true },
			{ edge }
		)
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
		raise(
			"thing_edges_changed",
			self,
			graph_name,
			"deleted",
			{ [self.id] = true, [other.id] = true },
			{ edge }
		)
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
		raise(
			"thing_edges_changed",
			self,
			graph_name,
			"deleted",
			node_set,
			edge_list
		)
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

---Add parent/child relationship between this Thing and `child`.
---@param key string|int
---@param child things.Thing
---@return boolean success True if the child was added, false if the child had a duplicate key or an existing parent.
function Thing:add_child(key, child)
	if not self.children then self.children = {} end
	if self.children[key] then return false end
	if child.parent then return false end
	self.children[key] = child
	local old_parent = child.parent
	child.parent = self
	child.child_key_in_parent = key
	raise("thing_children_changed", self, child, nil)
	raise("thing_parent_changed", child, old_parent and old_parent.id or nil)
	return true
end

---@param filter nil|string|int|things.Thing|fun(child: things.Thing, key: string|int): boolean Filter for children to remove. If `nil`, removes all children. If a string or number, interpreted as a key. If a Thing, interpreted as a specific child. If a function, called with each child and its key; should return true to remove the child.
---@return things.Thing[]|nil removed_children
function Thing:remove_children(filter)
	local children = self.children
	if not children then return nil end
	-- Allow filtering by key or specific child.
	local t_filter, val_filter = type(filter), filter
	if t_filter == "string" or t_filter == "number" then
		filter = function(_, key) return key == val_filter end
	elseif t_filter == "table" then
		filter = function(child) return child == val_filter end
	end
	local removed = {}
	for key, child in pairs(children) do
		if filter and not filter(child, key) then goto continue end
		if child.parent ~= self then
			debug_crash(
				"Thing:remove_children: child Thing has different parent, RI failure",
				self.id,
				child.id,
				child.parent and child.parent.id or nil
			)
			goto continue
		end
		child.parent = nil
		child.child_key_in_parent = nil
		children[key] = nil
		removed[#removed + 1] = child
		raise("thing_parent_changed", child, self.id)
		::continue::
	end
	if not next(children) then self.children = nil end
	if #removed > 0 then raise("thing_children_changed", self, nil, removed) end
	return removed
end

function Thing:on_changed_state(new_state, old_state)
	-- If silent, skip all events.
	if self.is_silent then return end
	raise("thing_status", self, old_state --[[@as string]])
	-- Parent/child status events
	if self.parent then
		raise("thing_child_status", self.parent, self, old_state --[[@as string]])
	end
	if self.children then
		for _, child in pairs(self.children) do
			raise("thing_parent_status", child, self, old_state --[[@as string]])
		end
	end
	-- Create on_edges_changed events
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
		raise(
			"thing_edges_changed",
			self,
			graph_name,
			"status_changed",
			node_set,
			edge_list
		)
		::continue::
	end
end

---Initialize the Thing's virtual orientation, if applicable. This should be
---called at the start of Thing lifecycle.
---@param bp_entity? BlueprintEntity If this Thing was built from a blueprint, the blueprint entity data.
---@param bp_transform? Core.Dihedral If this Thing was built from a blueprint, the blueprint's overall transformation.
function Thing:init_virtual_orientation(bp_entity, bp_transform)
	local reg = self.registration
	if not reg or not reg.virtualize_orientation then return end
	if bp_entity and bp_transform then
		-- Blueprint case
		local O = nil
		if self.tags[ORIENTATION_TAG] then
			-- Already has virtual orientation
			O = orientation_lib.from_data(
				self.tags[ORIENTATION_TAG] --[[@as Core.OrientationData]]
			)
		else
			-- Get base orientation within the BP
			debug_log(
				"Thing:init_virtual_orientation: probably should have had an orientation from tags, but we're synthesizing one from the BP entity",
				self.id,
				bp_entity
			)
			-- TODO: we could be smarter about this; look at name and type
			O = orientation_lib.Orientation:new(OC_048CM_RF)
			O[3] = bp_entity.direction or 0
			O[4] = bp_entity.mirror and 0 or 1
		end
		---@cast O Core.Orientation
		-- Apply BP transform
		debug_log("pre_transform", O, bp_transform)
		O:apply_blueprint_transform(bp_transform)
		debug_log("post_transform", O)
		self:set_virtual_orientation(O)
	elseif self.entity and self.entity.valid then
		-- Non-blueprint case
		if self.tags[ORIENTATION_TAG] then
			-- Already has virtual orientation
			-- TODO: orientation consistency check
			local O = orientation_lib.from_data(
				self.tags[ORIENTATION_TAG] --[[@as Core.OrientationData]]
			)
			self.virtual_orientation = O
			return
		else
			local O = orientation_lib.extract_orientation(self.entity)
			if not O then
				debug_crash(
					"Thing:init_virtual_orientation: could not extract orientation from entity",
					self.id,
					self.entity
				)
				return
			end
			debug_log("new entity with virtual orientation", self.id, O)
			self:set_virtual_orientation(O)
		end
	end
end

---@param O Core.Orientation
function Thing:set_virtual_orientation(O)
	if not self.registration or not self.registration.virtualize_orientation then
		return
	end
	self.virtual_orientation = O
	self:set_tag(ORIENTATION_TAG, O:to_data())
end

---Rotate this thing's virtual orientation if enabled.
---@param ccw boolean? If true, rotate counterclockwise; otherwise clockwise.
function Thing:virtual_rotate(ccw)
	if not self.virtual_orientation then return end
	local O = self.virtual_orientation:clone()
	if not O then return end
	local R = ccw and O:Rinv(WORLD_ORIENTATION) or O:R(WORLD_ORIENTATION)
	O:apply(R)
	-- debug_log("virtual_rotate", self.id, self.virtual_orientation, R, O)
	self:set_virtual_orientation(O)
end

---Flip this thing's virtual orientation if enabled.
---@param horizontal boolean? If true, flip horizontally; otherwise vertically.
function Thing:virtual_flip(horizontal)
	if not self.virtual_orientation then return end
	local O = self.virtual_orientation:clone()
	if not O then return end
	local F = horizontal and O:H(WORLD_ORIENTATION) or O:V(WORLD_ORIENTATION)
	O:apply(F)
	self:set_virtual_orientation(O)
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
	thing:set_entity(entity, key)
	thing:update_registration()
	thing.state_cause = "created"
	thing.is_silent = true
	thing:init_virtual_orientation()
	thing:apply_status()
	thing.is_silent = nil
	thing:initialize()
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
		}, { skip = defines.print_skip.never, sound = defines.print_sound.always })
	end
	tg[key] = thing.id
end

---Removed a marked Thing ghost from storage.
---@param key Core.WorldKey
function _G.clear_thing_ghost(key) storage.thing_ghosts[key] = nil end

---@param op things.ConstructionOperation
---@return boolean #True if a ghost was revived, false otherwise.
function _G.mark_revived_ghost(op)
	local entity = op.entity
	local key = op.key
	local revived_ghost_id = storage.thing_ghosts[key]
	if not revived_ghost_id then return false end

	clear_thing_ghost(key)
	debug_log("Revived Thing ghost at", key)
	local thing = get_thing(revived_ghost_id)
	if thing then
		thing:revived_from_ghost(entity, key)
	else
		debug_crash(
			"built_real: referential integrity failure: no Thing matching revived ghost id",
			revived_ghost_id,
			entity
		)
	end
	return true
end
