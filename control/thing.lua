local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local StateMachine = require("lib.core.state-machine")
local entities = require("lib.core.entities")
local lib_pos = require("lib.core.math.pos")

local pos_close = lib_pos.pos_close
local pos_get = lib_pos.pos_get

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
	---Thing was revived from a ghost
	alive_revived = "alive_revived",
	---Thing is destroyed but remaining as an undo tombstone.
	tombstone = "tombstone",
	---A matching ghost has been built over this Thing's tombstone; waiting
	---for an undo operation for revival.
	tombstone_maybe_undo = "tombstone_maybe_undo",
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
---@class things.Thing: StateMachine
---@field public id int Unique gamewide id for this Thing.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public local_id? int If this Thing came from a blueprint, its local id within that blueprint.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, must be checked for validity each time used.
---@field public debug_overlay? Core.MultiLineTextOverlay Debug overlay for this Thing.
---@field public tags Tags The tags associated with this Thing.
---@field public tombstone_key? string If this Thing is an undo tombstone, its key.
---@field public tombstone_tick? uint If this Thing is an undo tombstone, the tick it was last seen.
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
	if entity and entity.valid and entity.type == "entity-ghost" then
		local tags = entity.tags or {}
		tags[key] = value
		entity.tags = tags
	end
end

---Attempt to locate an undo record for this Thing on the player's undo stack.
---If found, tag it with this Thing's id for later retrieval.
---@param player LuaPlayer?
function Thing:tag_undo_record(player)
	if self.has_undo_record then return end
	if
		not player
		or not player.valid
		or not self.entity
		or not self.entity.valid
	then
		return
	end
	local undo_item = player.undo_redo_stack.get_undo_item(1)
	if not undo_item then return end
	for action_index, action in pairs(undo_item) do
		if
			action.type == "built-entity"
			and action.target.name == self.entity.name
			and action.surface_index == self.entity.surface_index
			and pos_close(action.target.position, self.entity.position)
		then
			player.undo_redo_stack.set_undo_tag(1, action_index, "@thing_id", self.id)
			debug_log(
				"tag_undo_record: tagged undo item",
				action_index,
				"for thing",
				self.id
			)
			self.has_undo_record = true
			return
		end
	end
end

---Called when this Thing's entity dies, leaving a ghost behind.
---@param ghost LuaEntity
function Thing:died_leaving_ghost(ghost)
	self.entity = ghost
	self:set_unit_number(ghost.unit_number)
	if self.tags then ghost.tags = self.tags end
	self:set_state("ghost_dead")
end

---Called when this Thing is revived from a ghost.
---@param revived_entity LuaEntity
---@param tags Tags?
function Thing:revived_from_ghost(revived_entity, tags)
	self.entity = revived_entity
	self:set_unit_number(revived_entity.unit_number)
	if tags then self.tags = tags end
	self:set_state("alive_revived")
end

---Create an undo tombstone for this Thing.
---@param death_entity LuaEntity
function Thing:tombstone(death_entity)
	local pos = death_entity.position
	local surface_index = death_entity.surface_index
	local _, prototype_name = entities.resolve_possible_ghost(death_entity)
	local x, y = pos_get(pos)
	self.tombstone_key =
		string.format("%2.2f:%2.2f:%d:%s", x, y, surface_index, prototype_name)
	self.tombstone_tick = game.tick
	storage.tombstones[self.tombstone_key] = self
	self:set_state("tombstone")
end

---Destroy this Thing. This is a terminal state and the Thing may not be
---reused from here.
function Thing:destroy()
	-- TODO: force destroy entity if needed
	self.entity = nil
	-- Remove from registry
	storage.things_by_unit_number[self.unit_number or ""] = nil
	--storage.tombstones[self.tombstone_key or ""] = nil
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

---Determine if a ghost entity might be an undo over a tombstone.
---If so, move the tombstone to a "maybe undo" state and return it.
function _G.maybe_undo_tombstone(ghost)
	if not ghost.valid or ghost.type ~= "entity-ghost" then return nil end
	local pos = ghost.position
	local surface_index = ghost.surface_index
	local _, prototype_name = entities.resolve_possible_ghost(ghost)
	local x, y = pos_get(pos)
	local key =
		string.format("%2.2f:%2.2f:%d:%s", x, y, surface_index, prototype_name)
	local tombstone = storage.tombstones[key]
	if not tombstone then return nil end
	if tombstone.state ~= "tombstone" then return nil end
	tombstone:set_state("tombstone_maybe_undo")
	return tombstone
end

---@param entity LuaEntity A *valid* LuaEntity with a `unit_number`
---@return boolean was_created True if a new Thing was created, false if the entity was already a Thing.
---@return things.Thing?
function _G.thingify_entity(entity)
	-- TODO: a maybe_undo_ghost can't be thingified on the same frame as it
	-- became an undo ghost.

	local thing = get_thing_by_unit_number(entity.unit_number)
	if thing then return false, thing end
	thing = Thing:new()
	thing.entity = entity
	thing:raw_set_tag("@ig", thing.id)
	thing:set_unit_number(entity.unit_number)
	if entity.type == "entity-ghost" then
		thing:set_state("ghost_initial")
	else
		thing:set_state("alive_initial")
	end
	return true, thing
end
