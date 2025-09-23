local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local entities = require("lib.core.entities")

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
---@class things.Thing: StateMachine
---@field public id int Unique gamewide id for this Thing.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public local_id? int If this Thing came from a blueprint, its local id within that blueprint.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, must be checked for validity each time used.
---@field public debug_overlay? Core.MultiLineTextOverlay Debug overlay for this Thing.
---@field public tags Tags The tags associated with this Thing.
local Thing = class("things.Thing", StateMachine)
_G.Thing = Thing

---@return things.Thing
function Thing:new()
	local id = counters.next("entity")
	local obj = StateMachine.new(self, "unknown")
	obj.id = id
	obj.tags = {}
	storage.things[id] = obj
	return obj
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

---Set a tag on this Thing without firing any events.
---@param key string
---@param value Tags|boolean|number|string|nil
function Thing:raw_set_tag(key, value)
	self.tags[key] = value
	local entity = self.entity
	if entity and entity.valid and entity.name == "entity-ghost" then
		local tags = entity.tags or {}
		tags[key] = value
		entity.tags = tags
	end
end

---Destroy this Thing. This is a terminal state and the Thing may not be
---reused from here.
function Thing:destroy()
	-- TODO: force destroy entity if needed
	self.entity = nil
	-- Remove from UN registry
	storage.things_by_unit_number[self.unit_number or ""] = nil
	-- Give downstream a last bite at the apple
	self:set_state("destroyed")
	-- Remove from global registry
	storage.things[self.id] = nil
end

function Thing:on_changed_state(new_state, old_state)
	raise_thing_lifecycle(self, new_state, old_state --[[@as string]])
	script.raise_event("things-on_thing_lifecycle", {
		thing_id = self.id,
		new_state = new_state,
		old_state = old_state,
	})
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
---@return boolean was_created True if a new Thing was created, false if the entity was already a Thing.
---@return things.Thing?
function _G.thingify_entity(entity)
	local thing = get_thing_by_unit_number(entity.unit_number)
	if thing then return false, thing end
	thing = Thing:new()
	thing.entity = entity
	thing:raw_set_tag("@ig", thing.id)
	thing:set_unit_number(entity.unit_number)
	if entity.name == "entity-ghost" then
		thing:set_state("initial_ghost")
	else
		thing:set_state("real")
	end
	return true, thing
end
