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

local pairs = pairs
local next = next
local type = type
local pos_get = pos_lib.pos_get
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local get_thing_registration = registration_lib.get_thing_registration
local o_loose_eq = orientation_lib.loose_eq
local NO_RAISE_DESTROY = { raise_destroy = false }
local RAISE_DESTROY = { raise_destroy = true }
local NO_RAISE_REVIVE = { raise_revive = false }
local EMPTY = tlib.EMPTY_STRICT

local lib = {}

---@alias things.UnthingChild [UnitNumber]

---@alias things.ChildDescriptor things.Id | things.UnthingChild

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
---@field public parent? things.ParentRelationshipInfo Information about this Thing's parent, if any.
---@field public children? table<string, things.ChildDescriptor> Map from child indices to child Thing descriptors.
---@field public transient_children? {[int|string]: LuaEntity} Map from child indices (which may be numbers or strings) to child entities that are not themselves Things.
---@field public ro_keys? {[string]: LuaRenderObject} List of named attached render objects.
---@field public ro_list? LuaRenderObject[] List of anonymous attached render objects.
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
		parent = self.parent,
		undo_refcount = self.undo_refcount,
	}
end

---Returns a short summary of a Thing.
---@return things.ThingShortSummary
function Thing:summarize_short()
	local entity = self.entity
	if entity and not entity.valid then entity = nil end
	return {
		id = self.id,
		name = self.name,
		entity = entity,
		status = self.state,
		virtual_orientation = self.virtual_orientation,
	}
end

---Determine if a Thing is valid (not destroyed). NOTE: this does NOT mean
---that the Thing necessarily has a valid world entity!
---@return boolean valid `true` if the Thing is valid, `false` if it is destroyed.
function Thing:is_valid() return self.state ~= "destroyed" end

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

---@param self things.Thing
local function internal_clear_transient_ros(self)
	if self.ro_keys then
		for _, ro in pairs(self.ro_keys) do
			if ro.valid then ro.destroy() end
		end
		self.ro_keys = nil
	end
	if self.ro_list then
		for _, ro in pairs(self.ro_list) do
			if ro.valid then ro.destroy() end
		end
		self.ro_list = nil
	end
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
		return
	end
	if entity == self.entity then return end
	-- Clear render_objects on entity change.
	internal_clear_transient_ros(self)
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
	strace.debug(
		"Thing:undo_maybe_destroy: Thing ID",
		self.id,
		"undo_refcount is zero and no live parent; garbage collecting."
	)
	self:destroy()
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
	strace.trace("Thing:destroy: destroying Thing ID", self.id)

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

	-- Remove from parent
	if self.parent and not skip_deparent then self:remove_parent() end

	-- Destroy children
	if self.children then
		for _, child_id in pairs(self.children) do
			if type(child_id) == "number" then
				local child_thing = storage.things[child_id]
				if child_thing then child_thing:destroy(true) end
			else
				remove_unthing_child(child_id[1], false, true)
			end
		end
		self.children = nil
	end

	-- Remove and potentially destroy self entity
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
		error(
			"LOGIC ERROR: Attempt to void a destroyed Thing. Thing ID: " .. self.id
		)
	end
	if self.state == "void" then return false end
	strace.trace("Thing:void: voiding Thing ID", self.id)

	-- Void children
	if self.children then
		for key, child_id in pairs(self.children) do
			if type(child_id) == "number" then
				local child_thing = storage.things[child_id]
				if child_thing then
					child_thing:void(skip_destroy_children, skip_destroy_children)
				end
			else
				-- Unthing children get destroyed on void.
				remove_unthing_child(child_id[1], false, true)
				self.children[key] = nil
			end
		end
	end

	-- Immediate-mode event for capturing state pre-void
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
---@return ItemWithQualityCount[]?
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
	-- Pure virtual case: return the virtual orientation if it exists.
	local vo = self.virtual_orientation
	if vo then
		local status = self.state
		if status == "ghost" or status == "real" then
			return vo
		else
			return nil
		end
	end

	-- Nonvirtual case: get from realized entity.
	local entity = self:get_entity()
	if not entity then return nil end
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
			strace.warn(
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

---Make this Thing's orientation virtual, if it isn't already. The orientation
---will be inferred from the entity.
---@param vo_class Core.OrientationClass
function Thing:virtualize_orientation(vo_class)
	local existing_vo = self.virtual_orientation
	if existing_vo and orientation_lib.get_class(existing_vo) == vo_class then
		return
	end
	local new_vo = orientation_lib.create(vo_class)
	local entity = self.entity
	if entity and entity.valid then
		local entity_orientation = orientation_lib.extract(entity)
		if entity_orientation then
			local _, direction, mirroring = orientation_lib.to_cdm(entity_orientation)
			new_vo = orientation_lib.from_cdm(vo_class, direction, mirroring)
		end
	end
	self.virtual_orientation = new_vo
end

---@param next_pos MapPosition
---@param next_surface_index? SurfaceIndex
function Thing:teleport(next_pos, next_surface_index)
	local entity = self:get_entity()
	if not entity then return false end
	local surface_index = entity.surface_index
	local pos = entity.position
	local same_surface = not next_surface_index
		or (next_surface_index == surface_index)
	if same_surface and pos_lib.pos_close(pos, next_pos) then return false end
	local target_surface = nil
	if not same_surface then target_surface = next_surface_index end
	if entity.teleport(next_pos, target_surface, false) then
		self:raise_event(
			"things.thing_position_changed",
			self,
			next_pos,
			pos,
			target_surface or surface_index,
			surface_index
		)
		return true
	else
		strace.error(
			"Thing:teleport: teleport failed for Thing ID",
			self.id,
			"to position",
			next_pos,
			"on surface",
			target_surface
		)
		return false
	end
end

---@param prev_pos MapPosition
---@param prev_surface_index? SurfaceIndex
function Thing:was_teleported(prev_pos, prev_surface_index)
	local entity = self:get_entity()
	if not entity then return false end
	local pos = entity.position
	local surface_index = entity.surface_index
	local same_surface = not prev_surface_index
		or (surface_index == prev_surface_index)
	if same_surface and pos_lib.pos_close(pos, prev_pos) then return false end
	self:raise_event(
		"things.thing_position_changed",
		self,
		pos,
		prev_pos,
		surface_index,
		prev_surface_index or surface_index
	)
	return true
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
	local transient_data = self.transient_data
	if transient_data then
		transient_data[key] = value
		if not next(transient_data) then self.transient_data = nil end
	else
		if value then
			transient_data = { [key] = value }
			self.transient_data = transient_data
		end
		return
	end
end

--------------------------------------------------------------------------------
-- PARENT CHILD RELATIONSHIPS
--------------------------------------------------------------------------------

---@param index string The index of the child.
---@param child things.Thing | LuaEntity The child to add.
---@param relative_pos? MapPosition The position of the child relative to this Thing.
---@param relative_orientation? Core.Dihedral The orientation of the child relative to this Thing.
---@param lifecycle_type? things.LifecycleType The lifecycle type of the child relative to this Thing. If not specified, defaults to "ghost-real".
---@param suppress_event boolean? If true, suppress parent/child change events.
function Thing:add_child(
	index,
	child,
	relative_pos,
	relative_orientation,
	lifecycle_type,
	suppress_event
)
	if not index then error("Thing:add_child(): index is required") end
	if self.children and self.children[index] then return false end
	if type(child) == "userdata" then
		-- Unthing child
		---@cast child LuaEntity
		local un = create_unthing_child(
			child,
			self,
			index,
			relative_pos,
			relative_orientation,
			lifecycle_type
		)
		if un then
			if not self.children then self.children = {} end
			self.children[index] = { un }
		else
			return false
		end

		self:raise_event("things.thing_children_changed", self, child, nil)
		return true
	else
		---@cast child things.Thing
		if child.parent then return false end
		if not self.children then self.children = {} end
		self.children[index] = child.id
		child.parent = {
			self.id,
			index,
			relative_pos,
			relative_orientation,
			lifecycle_type,
		}

		-- Post events as needed.
		if not suppress_event then
			self:raise_event("things.thing_children_changed", self, child, nil)
			child:raise_event("things.thing_parent_changed", child, self)
		end

		return true
	end
end

---@param index string The index of the child.
---@return boolean has_child `true` if a child Thing is present at the given index, `false` otherwise.
function Thing:has_child(index)
	if not index then return false end
	local children = self.children
	if not children then return false end
	return children[index] ~= nil
end

---Find the parent-most Thing in the parent-child-tree that this Thing is part of. If this Thing has no parent, returns itself.
---@return things.Thing root_thing The root-most Thing in the parent-child-tree that this Thing is part of.
function Thing:get_root()
	local parent_relationship = self.parent
	if not parent_relationship then return self end
	local parent_thing = storage.things[parent_relationship[1]]
	if not parent_thing then return self end
	return parent_thing:get_root()
end

---Remove this Thing's parent, if any.
---@return boolean removed `true` if a parent was removed, `false` if there was no parent.
function Thing:remove_parent()
	local parent_relationship = self.parent
	if not parent_relationship then return false end
	local parent_id, child_key = parent_relationship[1], parent_relationship[2]
	local parent_thing = storage.things[parent_id]
	local my_id = parent_thing
		and parent_thing.children
		and parent_thing.children[child_key]

	if (not parent_thing) or (my_id ~= self.id) then
		self.parent = nil
		strace.warn(
			"Thing:remove_parent: REFERENTIAL INTEGRITY FAILURE: parent Thing ID",
			parent_id,
			"does not have this Thing ID",
			self.id,
			"as its child at index",
			child_key
		)
		self:raise_event("things.thing_parent_changed", self)
		return true
	end

	self.parent = nil
	-- No nilcheck needed here as it would have been rejected above.
	---@diagnostic disable-next-line: need-check-nil
	parent_thing.children[child_key] = nil

	parent_thing:raise_event(
		"things.thing_children_changed",
		parent_thing,
		nil,
		self
	)
	self:raise_event("things.thing_parent_changed", self)
	return true
end

---@param index string The index of the child to remove.
---@param destroy_child boolean? If true, destroy the child Thing or Unthing. If false or nil, just remove it from the parent.
---@return boolean removed `true` if a child was removed, `false` if there was no child at that index.
function Thing:remove_child(index, destroy_child)
	local children = self.children
	if not children then return false end
	local child_id = children[index]
	if not child_id then return false end
	if type(child_id) == "number" then
		children[index] = nil
		local child_thing = storage.things[child_id]
		if not child_thing then
			strace.warn(
				"Thing:remove_child: REFERENTIAL INTEGRITY FAILURE: child Thing ID",
				child_id,
				"not found in storage for parent Thing ID",
				self.id
			)
			return true
		end
		local parent_relationship = child_thing.parent
		if (not parent_relationship) or (parent_relationship[1] ~= self.id) then
			strace.warn(
				"Thing:remove_child: REFERENTIAL INTEGRITY FAILURE: child Thing ID",
				child_id,
				"does not have this Thing ID",
				self.id,
				"as its parent."
			)
			return true
		end

		child_thing.parent = nil
		self:raise_event("things.thing_children_changed", self, nil, child_thing)
		if destroy_child then
			child_thing:destroy(false, true)
		else
			child_thing:raise_event("things.thing_parent_changed", child_thing)
		end
		return true
	else
		children[index] = nil
		local un = child_id[1]
		remove_unthing_child(un, false, destroy_child)
		return true
	end
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
		parent_thing:get_entity(),
		parent_thing:get_orientation(),
		parent_relationship[3],
		parent_relationship[4]
	)
end

---Recursively reorient this Thing with respect to its parent.
---@param no_recurse? boolean? If true, do not reorient children.
---@param no_self? boolean? If true, do not reorient self.
function Thing:reorient(no_recurse, no_self)
	-- Reorient self first, then children.
	local entity = self:get_entity()
	if not entity then return end
	if not no_self then
		local adj_pos, adj_orientation = self:get_adjusted_pos_and_orientation()
		if adj_pos then
			if self:teleport(adj_pos) then
				strace.trace(
					"Thing:reorient: adjusted position for Thing ID",
					self.id,
					"to",
					adj_pos
				)
			end
		end
		if adj_orientation then self:set_orientation(adj_orientation, true) end
	end

	if (not no_recurse) and self.children then
		for _, child in pairs(self.children) do
			if type(child) == "number" then
				local child_thing = storage.things[child]
				if child_thing then child_thing:reorient() end
			else
				local rel = get_unthing_child(child[1])
				if rel then
					local child_pos, child_or = lib.get_adjusted_pos_and_orientation(
						entity,
						self:get_orientation(),
						rel[3],
						rel[4]
					)
					if child_pos then
						-- TODO: unthing child
					end
					if child_or then
						-- TODO: unthing child
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- EVENT HANDLING
--------------------------------------------------------------------------------

---@param from_blueprint boolean? If true, this Thing was initialized from a blueprint.
function Thing:initialize(from_blueprint)
	local frame = in_frame()
	if frame then
		frame:post_event("things.thing_initialized", self, from_blueprint)
	else
		strace.trace(
			"Raising inline Thing event things.thing_initialized for Thing ID",
			self.id,
			"from_blueprint",
			from_blueprint
		)
		events.raise("things.thing_initialized", self, from_blueprint)
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
			if type(child) == "number" then
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
	for _, graph in graph_lib.iterate_graphs_containing_node(self.id) do
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
-- RENDER OBJECTS
--------------------------------------------------------------------------------

---@param key string?
---@param ro LuaRenderObject?
function Thing:attach_transient_ro(key, ro)
	if key then
		local by_key = self.ro_keys
		if not by_key then
			by_key = {}
			self.ro_keys = by_key
		end
		local previous = by_key[key]
		if previous and previous.valid then previous.destroy() end
		by_key[key] = ro
	elseif ro then
		self.ro_list = self.ro_list or {}
		table.insert(self.ro_list, ro)
	end
end

---@param key string?
---@return LuaRenderObject?
function Thing:get_transient_ro(key)
	if not key then return nil end
	return self.ro_keys and self.ro_keys[key]
end

--------------------------------------------------------------------------------
-- GLOBALS
--------------------------------------------------------------------------------

---Get a Thing by its unique gamewide ID.
---@param id int64?
---@return things.Thing|nil
function lib.get_by_id(id)
	if not id then return nil end
	return storage.things[id]
end
get_thing_by_id = lib.get_by_id

---Get a Thing by the unit number of its entity.
---@param unit_number uint64?
---@return things.Thing|nil
function lib.get_by_unit_number(unit_number)
	if not unit_number then return nil end
	return storage.things_by_unit_number[unit_number]
end
get_thing_by_unit_number = lib.get_by_unit_number

---General thingification procedure for generic entities. This will
---return a SILENT thing that needs to be initialized later.
---@param entity LuaEntity A *valid* entity that isn't already a Thing.
---@param thing_name string The registration name of the Thing to create.
---@return things.Thing|nil thing The created or found Thing.
---@return boolean was_created True if a new Thing was created, false if an existing Thing was found.
---@return string|nil err An error message if something went wrong.
function lib.make_thing(entity, thing_name)
	local prev_thing = storage.things_by_unit_number[
		entity.unit_number --[[@as int64]]
	]
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
		thing:virtualize_orientation(reg.virtualize_orientation)
	end
	return thing, true, nil
end

---Get adjusted position and orientation values for a child Thing based on its
---relationship to its parent.
---@param parent_entity LuaEntity? The parent entity.
---@param parent_orientation Core.Orientation? The orientation of the parent entity.
---@param offset MapPosition? The position of the child relative to the parent.
---@param transform Core.Dihedral? The transform of the child relative to the parent.
---@return MapPosition? adjusted_pos The adjusted world position, or `nil` if no relative offset is specified.
---@return Core.Orientation? adjusted_orientation The adjusted world orientation, or `nil` if no relative offset is specified.
function lib.get_adjusted_pos_and_orientation(
	parent_entity,
	parent_orientation,
	offset,
	transform
)
	if not parent_entity then return nil, nil end
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
