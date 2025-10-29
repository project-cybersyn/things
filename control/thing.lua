local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local constants = require("control.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local oclass_lib = require("lib.core.orientation.orientation-class")
local dih_lib = require("lib.core.math.dihedral")
local registration_lib = require("control.registration")
local tlib = require("lib.core.table")
local events = require("lib.core.event")
local strace = require("lib.core.strace")
local pos_lib = require("lib.core.math.pos")
local graph_lib = require("control.graph")

local pos_get = pos_lib.pos_get
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local get_thing_registration = registration_lib.get_thing_registration
local o_loose_eq = orientation_lib.loose_eq
local NO_RAISE_DESTROY = { raise_destroy = false }
local NO_RAISE_REVIVE = { raise_revive = false }
local EMPTY = tlib.EMPTY_STRICT

local lib = {}

---A `Thing` is the extended lifecycle of a collection of game entities that
---actually represent the same ultimate thing.
---@class (exact) things.Thing: StateMachine
---@field public id int64 Unique gamewide id for this Thing.
---@field public state things.Status Current lifecycle state of this Thing.
---@field public name string Registration name of this Thing.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, **MUST** be checked for validity each time used.
---@field public created_by? uint64 The player index of the player who created this Thing, if any.
---@field public virtual_orientation? Core.Orientation If this class of Thing has virtual orientation, this is its current virtual orientation. This field is read-only.
---@field public is_silent? boolean If true, suppress events for this Thing.
---@field public tags? Tags The tags associated with this Thing.
---@field public transient_data? table Custom transient data associated with this Thing. This will NOT be blueprinted.
---@field public undo_refcount uint Number of undo records currently referencing this Thing.
---@field public last_known_position? MapPosition The last known position of this Thing's entity when the Thing is voided or destroyed.
---@field public graph_set? {[string]: true} Set of graph names this Thing is a member of. If `nil`, the Thing is not a member of any graphs.
---@field public parent? things.ParentRelationshipInfo Information about this Thing's parent, if any.
---@field public children? {[int|string]: int64} Map from child indices (which may be numbers or strings) to child Thing ids.
local Thing = class("things.Thing", StateMachine)
lib.Thing = Thing

---@param name string Registration name of this Thing.
---@return things.Thing
function Thing:new(name)
	local id = counters.next("thing")
	local obj = StateMachine.new(self, "void") --[[@as things.Thing]]
	obj.id = id
	obj.name = name
	obj.undo_refcount = 0
	storage.things[id] = obj
	return obj
end

--------------------------------------------------------------------------------
-- CORE
--------------------------------------------------------------------------------

---Summarizes a Thing for remote interface output.
---@return things.ThingSummary
function Thing:summarize()
	local entity = self.entity
	if entity and not entity.valid then entity = nil end
	return {
		id = self.id,
		name = self.name,
		entity = entity,
		status = self.state,
		virtual_orientation = self.virtual_orientation,
		tags = self.tags,
		graph_set = self.graph_set,
		parent = self.parent,
	}
end

function Thing:get_registration() return get_thing_registration(self.name) end

---@param skip_validation boolean? If falsy, and the Thing has an entity, ensure the entity is still valid.
function Thing:get_entity(skip_validation)
	local entity = self.entity
	if not skip_validation and entity and not entity.valid then return nil end
	return entity
end

---@param unit_number uint64?
local function internal_set_unit_number(self, unit_number)
	if self.unit_number == unit_number then return end
	storage.things_by_unit_number[self.unit_number or ""] = nil
	self.unit_number = unit_number
	if unit_number then storage.things_by_unit_number[unit_number] = self end
end

---@param entity LuaEntity?
---@param apply_status boolean? If true, update the thing's state inline.
function Thing:set_entity(entity, apply_status)
	if entity and self.state == "destroyed" then
		debug_crash(
			"Thing:set_entity: cannot set entity on destroyed Thing",
			self.id,
			entity
		)
	end
	if entity == self.entity then return end
	if not entity or not entity.valid then
		self.entity = nil
		internal_set_unit_number(self, nil)
		return
	end
	self.entity = entity
	local unit_number = entity.unit_number
	internal_set_unit_number(self, unit_number)
	local is_ghost = entity.type == "entity-ghost"
	if is_ghost then
		local tags = entity.tags or {}
		tags[GHOST_REVIVAL_TAG] = self.id
		entity.tags = tags
	end
	if apply_status then
		if is_ghost then
			self:set_state("ghost")
		else
			self:set_state("real")
		end
	end
end

function Thing:undo_ref() self.undo_refcount = self.undo_refcount + 1 end

function Thing:undo_unref()
	self.undo_refcount = self.undo_refcount - 1
	if self.undo_refcount <= 0 then
		self.undo_refcount = 0
		self:undo_maybe_destroy()
	end
end

function Thing:undo_maybe_destroy()
	if self.state ~= "void" then return end
	local parent_relationship = self.parent
	local parent_thing = parent_relationship
		and storage.things[parent_relationship[1]]
	if
		parent_thing
		and (parent_thing.state == "real" or parent_thing.state == "ghost")
	then
		-- Parent is alive; do not destroy.
		return
	end
	-- TODO: no-gc flag
	strace.trace(
		"Thing:undo_maybe_destroy: Thing ID",
		self.id,
		"undo_refcount is zero and no live parent; garbage collecting."
	)
end

--------------------------------------------------------------------------------
-- LIFECYCLE
--------------------------------------------------------------------------------

---Irreversibly and immediately destroy this Thing. By default, also destroy
---its associated entity.
---@param skip_destroy boolean? If true, skip destroying the Thing's entity.
---@param skip_deparent boolean? If true, skip removing this Thing from its parent.
function Thing:destroy(skip_destroy, skip_deparent)
	if self.state == "destroyed" then return end
	strace.debug("Thing:destroy: destroying Thing ID", self.id)
	local reg = self:get_registration() --[[@as things.ThingRegistration]]
	-- Disconnect all graph edges
	local graphs = graph_lib.get_graphs_containing_node(self.id)
	for _, graph in pairs(graphs or EMPTY) do
		local out_edges, in_edges = graph:get_edges(self.id)
		for to_id in pairs(out_edges) do
			graph_lib.disconnect(graph, self, storage.things[to_id])
		end
		for from_id in pairs(in_edges) do
			graph_lib.disconnect(graph, storage.things[from_id], self)
		end
	end
	if self.parent and not skip_deparent then self:remove_parent() end
	-- Destroy children
	if self.children and not reg.no_destroy_children_on_destroy then
		for _, child_id in pairs(self.children) do
			local child_thing = storage.things[child_id]
			if child_thing then child_thing:destroy(true) end
		end
		self.children = nil
	end
	local former_entity = self.entity
	self:set_entity(nil)
	self:set_state("destroyed")
	storage.things[self.id] = nil
	if not skip_destroy and former_entity and former_entity.valid then
		strace.trace("Thing:destroy: destroying entity for Thing ID", self.id)
		former_entity.destroy(NO_RAISE_DESTROY)
	end
end

---@param skip_destroy boolean? If true, skip destroying the Thing's entity.
---@param skip_destroy_children boolean? If true, skip destroying this Thing's children.
---@return boolean changed `true` if the Thing was voided, `false` if it was already void.
function Thing:void(skip_destroy, skip_destroy_children)
	if self.state == "destroyed" then
		error("Attempt to void a destroyed Thing. Thing ID: " .. self.id)
	end
	if self.state == "void" then return false end
	strace.debug("Thing:void: voiding Thing ID", self.id)
	local reg = self:get_registration() --[[@as things.ThingRegistration]]
	-- Void children
	if self.children and not reg.no_void_children_on_void then
		for _, child_id in pairs(self.children) do
			local child_thing = storage.things[child_id]
			if child_thing then child_thing:void(skip_destroy_children) end
		end
	end
	events.raise("things.thing_immediate_voided", self)
	local former_entity = self.entity
	self:set_entity(nil)
	self:set_state("void")
	if not skip_destroy and former_entity and former_entity.valid then
		former_entity.destroy(NO_RAISE_DESTROY)
	end
	return true
end

---@param entity LuaEntity A *valid* entity to associate with this Thing.
---@return boolean changed `true` if the Thing was devoided, `false` if it was not in the void state.
function Thing:devoid(entity)
	if self.state ~= "void" then return false end
	self:set_entity(entity, true)
	return true
end

function Thing:tombstone()
	if self.undo_refcount > 0 then
		strace.trace(
			"Thing:tombstone: Thing ID",
			self.id,
			"will be tombstoned; undo_refcount is",
			self.undo_refcount
		)
		self:void(true, false)
	else
		self:destroy()
	end
end

---Scripted revive for a ghosted thing. Triggers only Things-internal events.
---Returns the values of the `LuaEntity.silent_revive` Lua API call.
---@return ItemWithQualityCounts?
---@return LuaEntity?
---@return LuaEntity?
function Thing:revive()
	if self.state ~= "ghost" then return nil end
	local entity = self:get_entity()
	if not entity then
		strace.error(
			"Thing:revive: cannot revive ghost Thing ID",
			self.id,
			"because its entity is missing."
		)
		return nil
	end
	local r1, r2, r3 = entity.silent_revive(NO_RAISE_REVIVE)
	if r2 then
		self:set_entity(r2, true)
	else
		return nil
	end
	return r1, r2, r3
end

---Die leaving a ghost, when possible.
---@return boolean died `true` if the Thing's entity was successfully killed, `false` otherwise.
function Thing:die()
	if self.state ~= "real" then
		strace.warn(
			"Thing:die: cannot die Thing ID",
			self.id,
			"because its state is not 'real'. Current state:",
			self.state
		)
		return false
	end
	local entity = self:get_entity()
	if not entity then
		strace.error(
			"Thing:die: cannot die Thing ID",
			self.id,
			"because its entity is missing."
		)
		return false
	end
	return entity.die()
end

--------------------------------------------------------------------------------
-- POS/ORIENTATION
--------------------------------------------------------------------------------

---@return Core.Orientation?
function Thing:get_orientation()
	-- TODO: allow this to run purely virtually
	local entity = self:get_entity()
	if not entity then return nil end
	local vo = self.virtual_orientation
	if vo then return vo end
	return orientation_lib.extract(entity)
end

---@param orientation Core.Orientation
---@param impose boolean? If true, impose the orientation on the Thing's entity
---@param suppress_event boolean? If true, suppress orientation change events.
---@return boolean changed `true` if the Thing's orientation was changed.
---@return boolean imposed `true` if the orientation was imposed on the entity.
function Thing:set_orientation(orientation, impose, suppress_event)
	local current_orientation = self:get_orientation()
	if not current_orientation then
		-- Virtual thingless case.
		current_orientation = self.virtual_orientation
		if current_orientation then
			if not o_loose_eq(current_orientation, orientation) then
				-- TODO: oclass matching/projection
				self.virtual_orientation = orientation
				if not suppress_event then
					self:raise_event(
						"things.thing_orientation_changed",
						self,
						orientation,
						current_orientation
					)
				end
				return true, false
			end
		else
			strace.debug(
				"Thing:set_orientation: called on a Thing with no current orientation. Ignoring."
			)
		end
		return false, false
	elseif not o_loose_eq(current_orientation, orientation) then
		local changed = false
		local imposed = false
		if self.virtual_orientation then
			-- TODO: check for matching oclass?
			self.virtual_orientation = orientation
			changed = true
		end
		local entity = self:get_entity()
		if not entity then return changed, false end
		-- TODO: check if config allows imposition
		if impose then
			local eo = orientation_lib.extract(entity)
			if not o_loose_eq(eo, orientation) then
				orientation_lib.impose(orientation, entity)
				imposed = true
				changed = true
			end
		end
		if not suppress_event then
			self:raise_event(
				"things.thing_orientation_changed",
				self,
				orientation,
				current_orientation
			)
		end
		return changed, imposed
	end
	return false, false
end

---@param next_pos MapPosition
function Thing:teleport(next_pos)
	local entity = self:get_entity()
	if not entity then return false end
	local pos = entity.position
	if pos_lib.pos_close(pos, next_pos) then return false end
	if entity.teleport(next_pos, nil, false) then
		self:raise_event("things.thing_position_changed", self, next_pos, pos)
		return true
	else
		strace.error(
			"Thing:teleport: teleport failed for Thing ID",
			self.id,
			"to position",
			next_pos
		)
		return false
	end
end

--------------------------------------------------------------------------------
-- DATA
--------------------------------------------------------------------------------

---@param tags Tags?
---@param no_copy boolean? If true, assign the tags table directly instead of deep-copying it.
---@param suppress_event boolean? If true, suppress tags change events.
---@param event_source? "api"|"engine" Source of the tag change event, if any.
function Thing:set_tags(tags, no_copy, suppress_event, event_source)
	if (not tags) and not self.tags then return end
	local previous_tags = self.tags
	if tags then
		if no_copy then
			self.tags = tags
		else
			self.tags = tlib.deep_copy(tags, true)
		end
	else
		self.tags = nil
	end

	-- Post events as needed.
	if not suppress_event then
		self:raise_event(
			"things.thing_tags_changed",
			self,
			self.tags,
			previous_tags,
			event_source or "engine"
		)
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

--------------------------------------------------------------------------------
-- PARENT CHILD RELATIONSHIPS
--------------------------------------------------------------------------------

---@param index? int|string The index of the child. If not provided, #children+1 is used.
---@param child things.Thing The child Thing to add.
---@param relative_pos? MapPosition The position of the child relative to this Thing.
---@param relative_orientation? Core.Dihedral The orientation of the child relative to this Thing.
---@param suppress_event boolean? If true, suppress parent/child change events.
function Thing:add_child(
	index,
	child,
	relative_pos,
	relative_orientation,
	suppress_event
)
	if child.parent then return false end
	if self.children and index and self.children[index] then return false end
	if not self.children then self.children = {} end
	if not index then index = #self.children + 1 end
	self.children[index] = child.id
	child.parent = {
		self.id,
		index,
		relative_pos,
		relative_orientation,
	}

	-- Post events as needed.
	if not suppress_event then
		self:raise_event("things.thing_children_changed", self, child, nil)
		child:raise_event("things.thing_parent_changed", child, self)
	end
end

---Remove this Thing's parent, if any.
---@return boolean removed `true` if a parent was removed, `false` if there was no parent.
function Thing:remove_parent()
	local parent_relationship = self.parent
	if not parent_relationship then return false end
	local parent_thing = storage.things[parent_relationship[1]]
	local child_key = parent_relationship[2]
	local my_id = parent_thing
		and parent_thing.children
		and parent_thing.children[child_key]

	if (not parent_thing) or (my_id ~= self.id) then
		self.parent = nil
		self:raise_event("things.thing_parent_changed", self)
		return true
	end

	self.parent = nil
	parent_thing.children[child_key] = nil

	parent_thing:raise_event(
		"things.thing_children_changed",
		parent_thing,
		nil,
		{ self }
	)
	self:raise_event("things.thing_parent_changed", self)
	return true
end

---If this Thing has a parent, and its relationship specifies a relative
---position and/or orientation, compute the WORLD orientation using the
---parent's current data plus the given relative offsets.
---@return MapPosition? adjusted_pos The adjusted world position, or `nil` if no relative offset is specified.
---@return Core.Orientation? adjusted_orientation The adjusted world orientation, or `nil` if no relative offset is specified.
function Thing:get_adjusted_pos_and_orientation()
	local parent_relationship = self.parent
	if not parent_relationship then return nil, nil end
	local parent_thing = storage.things[parent_relationship[1]]
	if not parent_thing then return nil, nil end
	return lib.get_adjusted_pos_and_orientation(
		parent_thing,
		parent_relationship[3],
		parent_relationship[4]
	)
end

---If this Thing has a parent, and its relationship specifies a relative
---position or orientation, apply those if needed.
function Thing:apply_adjusted_pos_and_orientation()
	local entity = self:get_entity()
	if not entity then return end
	local adj_pos, adj_orientation = self:get_adjusted_pos_and_orientation()
	if adj_pos then
		strace.trace(
			"Thing:apply_adjusted_pos_and_orientation: computed adjusted position for Thing ID",
			self.id,
			"parent-index",
			self.parent and self.parent[2],
			"as",
			adj_pos
		)
		if self:teleport(adj_pos) then
			strace.trace(
				"Thing:apply_adjusted_pos_and_orientation: adjusted position for Thing ID",
				self.id,
				"to",
				adj_pos
			)
		end
	end
	if adj_orientation then self:set_orientation(adj_orientation, true) end
end

--------------------------------------------------------------------------------
-- EVENT HANDLING
--------------------------------------------------------------------------------

function Thing:initialize()
	local frame = in_frame()
	if frame then
		frame:post_event("things.thing_initialized", self)
	else
		strace.trace(
			"Raising inline Thing event",
			"things.thing_initialized",
			"for Thing ID",
			self.id
		)
		events.raise("things.thing_initialized", self)
	end
end

function Thing:raise_event(event_name, ...)
	if self.is_silent then return end
	local frame = in_frame()
	if frame then
		frame:post_event(event_name, ...)
	else
		strace.trace(
			"Raising inline Thing event",
			event_name,
			"for Thing ID",
			self.id
		)
		events.raise(event_name, ...)
	end
end

function Thing:on_changed_state(new_state, old_state)
	-- If silent, skip all events.
	if self.is_silent then return end
	local raise = events.raise
	local frame = in_frame()
	if frame then
		raise = function(event_name, ...) frame:post_event(event_name, ...) end
	end
	-- Notify children first.
	if self.children then
		for _, child in pairs(self.children) do
			local child_thing = storage.things[child]
			if child_thing then
				raise(
					"things.thing_parent_status",
					child_thing,
					self,
					old_state --[[@as string]]
				)
			end
		end
	end
	-- Notify self
	raise("things.thing_status", self, old_state --[[@as string]])
	-- Notify parent
	local parent_relationship = self.parent
	if parent_relationship then
		local parent_thing = storage.things[parent_relationship[1]]
		if parent_thing then
			raise(
				"things.thing_child_status",
				parent_thing,
				parent_relationship[2],
				self,
				old_state --[[@as string]]
			)
		end
	end

	-- Notify graph peers
	for _, graph in pairs(graph_lib.get_graphs_containing_node(self.id)) do
		local out_edges, in_edges = graph:get_edges(self.id)
		for to_id, edge in pairs(out_edges) do
			local thing = storage.things[to_id]
			if thing then
				raise("things.thing_edge_status", thing, self, graph, edge, old_state)
			end
		end
		for from_id, edge in pairs(in_edges) do
			local thing = storage.things[from_id]
			if thing then
				raise("things.thing_edge_status", thing, self, graph, edge, old_state)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- GLOBALS
--------------------------------------------------------------------------------

---Get a Thing by its unique gamewide ID.
---@param id int64
---@return things.Thing|nil
function lib.get_by_id(id) return storage.things[id] end
_G.get_thing_by_id = lib.get_by_id

---Get a Thing by the unit number of its entity.
---@param unit_number uint64?
---@return things.Thing|nil
function lib.get_by_unit_number(unit_number)
	return storage.things_by_unit_number[unit_number or ""]
end
_G.get_thing_by_unit_number = lib.get_by_unit_number

---General thingification procedure for generic entities. This will
---return a SILENT thing that needs to be initialized later.
---@param entity LuaEntity A *valid* entity that isn't already a Thing.
---@param thing_name string The registration name of the Thing to create.
---@return things.Thing|nil thing The created or found Thing.
---@return boolean was_created True if a new Thing was created, false if an existing Thing was found.
---@return string|nil err An error message if something went wrong.
function lib.make_thing(entity, thing_name)
	local prev_thing = storage.things_by_unit_number[entity.unit_number or ""]
	if prev_thing then
		if prev_thing.name == thing_name then
			return prev_thing, false, nil
		else
			return nil,
				false,
				string.format(
					"make_thing: entity unit_number %d already associated with Thing ID %d of type '%s', differing from desired type '%s'",
					entity.unit_number,
					prev_thing.id,
					prev_thing.name,
					thing_name
				)
		end
	end

	local reg = get_thing_registration(thing_name)
	if not reg then
		return nil,
			false,
			string.format("make_thing: no such thing registration '%s'", thing_name)
	end
	local thing = Thing:new(thing_name)
	thing.is_silent = true
	thing:set_entity(entity, true)
	if reg.virtualize_orientation then
		local entity_orientation = orientation_lib.extract(entity)
		if not entity_orientation then
			error("Could not extract orientation from entity")
		end
		local eclass, order, r, s = orientation_lib.decode_wide(entity_orientation)
		local eprops = oclass_lib.get_class_properties(eclass)
		local vprops = oclass_lib.get_class_properties(reg.virtualize_orientation)
		if eprops.dihedral_r_order ~= vprops.dihedral_r_order then
			error(
				"Entity orientation class "
					.. oclass_lib.stringify(eclass)
					.. " incompatible with Thing virtual orientation class "
					.. oclass_lib.stringify(reg.virtualize_orientation)
					.. ". Cannot raise dihedral_r_order."
			)
		end
		local vo =
			orientation_lib.encode_wide(reg.virtualize_orientation, order, r, s)
		thing.virtual_orientation = vo
	end
	return thing, true, nil
end

---Get adjusted position and orientation values for a child Thing based on its
---relationship to its parent.
---@param parent_thing things.Thing
---@param offset MapPosition? The position of the child relative to the parent.
---@param transform Core.Dihedral? The transform of the child relative to the parent.
---@return MapPosition? adjusted_pos The adjusted world position, or `nil` if no relative offset is specified.
---@return Core.Orientation? adjusted_orientation The adjusted world orientation, or `nil` if no relative offset is specified.
function lib.get_adjusted_pos_and_orientation(parent_thing, offset, transform)
	local parent_entity = parent_thing:get_entity()
	if not parent_entity then return nil, nil end
	local parent_orientation = parent_thing:get_orientation()
	if not parent_orientation then return nil, nil end
	-- Position
	local adj_pos = nil
	if offset then
		offset = orientation_lib.transform_vector(parent_orientation, offset)
		local offset_x, offset_y = pos_get(offset)
		local parent_x, parent_y = pos_get(parent_entity.position)
		adj_pos = {
			parent_x + offset_x,
			parent_y + offset_y,
		}
	end
	-- Orientation
	local adj_orientation = nil
	if transform then
		adj_orientation = orientation_lib.apply(parent_orientation, transform)
	end
	return adj_pos, adj_orientation
end

return lib
