local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local constants = require("control.constants")
local orientation_lib = require("lib.core.orientation.orientation")
local oclass_lib = require("lib.core.orientation.orientation-class")

local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG

local lib = {}

---Get a Thing by its unique gamewide ID.
---@param id int64
---@return things.Thing|nil
function lib.get_by_id(id) return storage.things[id] end

---Get a Thing by the unit number of its entity.
---@param unit_number uint64?
---@return things.Thing|nil
function lib.get_by_unit_number(unit_number)
	return storage.things_by_unit_number[unit_number or ""]
end

---A `Thing` is the extended lifecycle of a collection of game entities that
---actually represent the same ultimate thing.
---@class (exact) things.Thing: StateMachine
---@field public id int64 Unique gamewide id for this Thing.
---@field public state things.Status Current lifecycle state of this Thing.
---@field public name string Registration name of this Thing.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, **MUST** be checked for validity each time used.
---@field public key Core.WorldKey? The world key of this Thing's entity, if any. Only valid to the extent `entity` exists and is valid.
---@field public virtual_orientation? Core.Orientation If this class of Thing has virtual orientation, this is its current virtual orientation. This field is read-only.
---@field public is_silent? boolean If true, suppress events for this Thing.
---@field public tags? Tags The tags associated with this Thing.
---@field public transient_data? table Custom transient data associated with this Thing. This will NOT be blueprinted.
---@field public last_known_position? MapPosition The last known position of this Thing's entity when the Thing is voided or destroyed.
---@field public graph_set? {[string]: true} Set of graph names this Thing is a member of. If `nil`, the Thing is not a member of any graphs.
---@field public parent? things.ParentRelationshipInfo Information about this Thing's parent, if any.
---@field public parent_thing? things.Thing Reference to this Thing's parent, if any.
---@field public children? {[int|string]: things.Thing} Map from child names (which may be numbers or strings) to child Things.
local Thing = class("things.Thing", StateMachine)
lib.Thing = Thing

---@param name string Registration name of this Thing.
---@return things.Thing
function Thing:new(name)
	local id = counters.next("thing")
	local obj = StateMachine.new(self, "void") --[[@as things.Thing]]
	obj.id = id
	obj.name = name
	storage.things[id] = obj
	return obj
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
		local tags = entity.tags or {}
		tags[GHOST_REVIVAL_TAG] = self.id
		entity.tags = tags
	end
end

---@return Core.Orientation?
function Thing:get_orientation()
	local entity = self:get_entity()
	if not entity then return nil end
	local vo = self.virtual_orientation
	if vo then return vo end
	return orientation_lib.extract_orientation(entity)
end

return lib
