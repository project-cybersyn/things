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

---@enum things.ThingState
local ThingState = {
	---Thing is a ghost that was manually thingified.
	ghost_initial = "ghost_initial",
	---Thing is ghost built from a blueprint.
	ghost_blueprint = "ghost_blueprint",
	---Thing is a ghost after its real entity died.
	ghost_died = "ghost_died",
	---Thing is a ghost that may be from undo.
	ghost_maybe_undo = "ghost_maybe_undo",
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
---@class things.Thing: StateMachine
---@field public id int Unique gamewide id for this Thing.
---@field public unit_number? uint The last-known-good `unit_number` for this Thing. May be `nil` or invalid.
---@field public local_id? int If this Thing came from a blueprint, its local id within that blueprint.
---@field public entity LuaEntity? Current entity representing the thing. Due to potential for lifecycle leaks, must be checked for validity each time used.
---@field public debug_overlay? Core.MultiLineTextOverlay Debug overlay for this Thing.
---@field public tags Tags The tags associated with this Thing.
---@field public last_known_position? MapPosition The last known position of this Thing's entity, if any.
---@field public n_undo_markers uint The number of undo markers currently associated with this Thing.
local Thing = class("things.Thing", StateMachine)
_G.Thing = Thing

---@return things.Thing
function Thing:new()
	local id = counters.next("entity")
	local obj = StateMachine.new(self, "unknown")
	obj.id = id
	obj.tags = {}
	obj.n_undo_markers = 0
	storage.things[id] = obj
	return obj
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
function Thing:built_as_tagged_ghost(ghost, tags)
	local local_id = tags["@i"]
	self.entity = ghost
	if tags["@t"] then self.tags = tags["@t"] end
	-- Re-tag ghost with Thing global ID.
	tags["@t"] = nil
	tags["@i"] = nil
	tags["@ig"] = self.id
	ghost.tags = tags
	self:set_unit_number(ghost.unit_number)
	self:set_state("ghost_blueprint")
end

---Thing was built as a tagged real entity, probably from a BP in cheat mode.
---@param entity LuaEntity A *valid* real entity.
---@param tags Tags The tags on the entity.
function Thing:built_as_tagged_real(entity, tags)
	local local_id = tags["@i"]
	self.entity = entity
	if tags["@t"] then self.tags = tags["@t"] end
	self:set_unit_number(entity.unit_number)
	self:set_state("alive_blueprint")
end

---Called when this Thing's entity dies, leaving a ghost behind.
---@param ghost LuaEntity
function Thing:died_leaving_ghost(ghost)
	self.entity = ghost
	self:set_unit_number(ghost.unit_number)
	ghost.tags = { ["@ig"] = self.id }
	self:set_state("ghost_dead")
end

---Called when this Thing is revived from a ghost.
---@param revived_entity LuaEntity
---@param tags Tags? The tags on the revived entity.
function Thing:revived_from_ghost(revived_entity, tags)
	self.entity = revived_entity
	self:set_unit_number(revived_entity.unit_number)
	self:set_state("alive_revived")
end

---Try to resurrect a potentially tombstoned entity that was revived via
---an undo operation. `entity` is previously calculated by the undo
---subsystem to be a suitably overlapping entity.
---@param entity LuaEntity A *valid* entity.
function Thing:undo_with(entity)
	if self.state ~= "tombstone" then return false end
	self.entity = entity
	self:set_unit_number(entity.unit_number)
	if entity.type == "entity-ghost" then
		entities.ghost_set_tag(entity, "@ig", self.id)
		self:set_state("ghost_undo")
	else
		self:set_state("alive_undo")
	end
	return true
end

---Convert this Thing to an undo ghost.
---@param ghost LuaEntity A *valid ghost* entity.
function Thing:to_undo_ghost(ghost)
	if self.state ~= "tombstone" then return false end
	self.entity = ghost
	entities.ghost_set_tag(ghost, "@ig", self.id)
	self:set_unit_number(ghost.unit_number)
	self:set_state("ghost_undo")
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
		debug_log(
			"Thing:entity_destroyed: entity mismatch, ignoring",
			self.id,
			self.entity,
			entity
		)
		return
	end
	self.last_known_position = entity.position
	self.entity = nil
	self:set_unit_number(nil)
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
	-- TODO: a maybe_undo_ghost can't be thingified on the same frame as it
	-- became an undo ghost.

	local thing = get_thing_by_unit_number(entity.unit_number)
	if thing then return false, thing end
	thing = Thing:new()
	thing.entity = entity
	if entity.type == "entity-ghost" then
		entities.ghost_set_tag(entity, "@ig", thing.id)
	end
	thing:set_unit_number(entity.unit_number)
	if entity.type == "entity-ghost" then
		thing:set_state("ghost_initial")
	else
		thing:set_state("alive_initial")
	end
	return true, thing
end
