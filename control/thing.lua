local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local constants = require("control.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local oclass_lib = require("lib.core.orientation.orientation-class")
local registration_lib = require("control.registration")
local tlib = require("lib.core.table")
local frame_lib = require("control.frame")
local events = require("lib.core.event")

local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local get_thing_registration = registration_lib.get_thing_registration

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
		if self.state == "void" then self:destroy() end
	end
end

function Thing:destroy()
	self:set_entity(nil)
	self:set_state("destroyed")
	storage.things[self.id] = nil
end

function Thing:tombstone()
	if self.undo_refcount > 0 then
		self:set_entity(nil)
		self:set_state("void")
	else
		self:destroy()
	end
end

---@return Core.Orientation?
function Thing:get_orientation()
	local entity = self:get_entity()
	if not entity then return nil end
	local vo = self.virtual_orientation
	if vo then return vo end
	return orientation_lib.extract(entity)
end

---@param orientation Core.Orientation
---@param impose boolean? If true, impose the orientation on the Thing's entity
function Thing:set_orientation(orientation, impose)
	if self.virtual_orientation then
		-- TODO: check for matching oclass?
		self.virtual_orientation = orientation
	end
	local entity = self:get_entity()
	if not entity then return end
	if impose then orientation_lib.impose(orientation, entity) end
end

---@param tags Tags?
---@param no_copy boolean? If true, assign the tags table directly instead of deep-copying it.
function Thing:set_tags(tags, no_copy)
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
	if self.is_silent then return end
	local frame = frame_lib.in_frame()
	if frame then
		frame:post_event(
			"things.thing_tags_changed",
			self,
			self.tags,
			previous_tags
		)
	else
		events.raise("things.thing_tags_changed", self, self.tags, previous_tags)
	end
end

---@param index int|string The index of the child.
---@param child things.Thing The child Thing to add.
---@param relative_pos? MapPosition The position of the child relative to this Thing.
---@param relative_orientation? Core.Dihedral The orientation of the child relative to this Thing.
function Thing:add_child(index, child, relative_pos, relative_orientation)
	if child.parent then return false end
	if self.children and self.children[index] then return false end
	if not self.children then self.children = {} end
	self.children[index] = child.id
	child.parent = {
		self.id,
		index,
		relative_pos,
		relative_orientation,
	}

	-- Post events as needed.
	if self.is_silent then return end
	local frame = frame_lib.in_frame()
	if frame then
		frame:post_event("things.thing_children_changed", self, child, nil)
		frame:post_event("things.thing_parent_changed", child)
	else
		events.raise("things.thing_children_changed", self, child, nil)
		events.raise("things.thing_parent_changed", child)
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
-- EVENT HANDLING
--------------------------------------------------------------------------------

function Thing:on_changed_state(new_state, old_state)
	-- If silent, skip all events.
	if self.is_silent then return end
	local raise = events.raise
	local frame = frame_lib.in_frame()
	if frame then
		raise = function(event_name, ...) frame:post_event(event_name, ...) end
	end
	-- Notify children first.
	if self.children then
		for _, child in pairs(self.children) do
			raise(
				"things.thing_parent_status",
				child,
				self,
				old_state --[[@as string]]
			)
		end
	end
	-- Notify self
	raise("things.thing_status", self, old_state --[[@as string]])
	-- Notify parent
	if self.parent then
		local parent_thing = storage.things[self.parent[1]]
		if parent_thing then
			raise(
				"things.thing_child_status",
				parent_thing,
				self,
				old_state --[[@as string]]
			)
		end
	end
	-- TODO: fix this graph shit
	-- Notify graph peers
	-- for graph_name in pairs(self.graph_set or EMPTY) do
	-- 	local graph = get_graph(graph_name)
	-- 	if not graph then goto continue end
	-- 	local edges = graph:get_edges(self.id)
	-- 	local edge_list = {}
	-- 	local node_set = {}
	-- 	node_set[self.id] = true
	-- 	for other_id, edge in pairs(edges) do
	-- 		table.insert(edge_list, edge)
	-- 		node_set[other_id] = true
	-- 	end
	-- 	raise(
	-- 		"thing_edges_changed",
	-- 		self,
	-- 		graph_name,
	-- 		"status_changed",
	-- 		node_set,
	-- 		edge_list
	-- 	)
	-- 	::continue::
	-- end
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
	thing:set_entity(entity)
	if entity.type == "entity-ghost" then
		thing:set_state("ghost")
	else
		thing:set_state("real")
	end
	if reg.virtualize_orientation then
		thing.virtual_orientation = orientation_lib.extract(entity)
	end
	return thing, true, nil
end

return lib
