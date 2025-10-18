local class = require("lib.core.class").class
local ws_lib = require("lib.core.world-state")
local constants = require("control.constants")
local events = require("lib.core.event")

local LOCAL_ID_TAG = constants.LOCAL_ID_TAG

local get_world_state = ws_lib.get_world_state

local lib = {}

---An individual operation.
---@class things.Operation: Core.WorldState
---@field public type string The type of this operation.
---@field public entity LuaEntity The entity involved in this operation.
---@field public player? LuaPlayer The player who initiated this operation, if any.
---@field public player_index? uint The index of the player who initiated this operation, if any.
---@field public thing? things.Thing The Thing associated with this operation, if any.
---@field public local_id? integer The local ID of the entity built by this operation within a blueprint, if any.
---@field public tags? Tags The tags associated with this operation, if any.
local Operation = class("things.Operation")
lib.Operation = Operation

---Create a new Operation.
---@param type string The type of this operation.
---@param entity LuaEntity A *valid* entity.
---@return things.Operation
function Operation:new(type, entity)
	local obj = setmetatable(get_world_state(entity), self) --[[@as things.Operation ]]
	obj.type = type
	obj.entity = entity
	return obj
end

function Operation:destroy() end

---A construction operation, i.e. building an entity or ghost.
---@class things.ConstructionOperation: things.Operation
---@field public is_ghost boolean `true` if this construction was of a ghost entity.
---@field public prebuilt? boolean `true` if this construction was part of a pre-build event.
---@field public undo_marker? things.UndoMarker The undo marker associated with this operation, if any.
---@field public vups? things.VirtualUndoPlayerState The virtual undo player state associated with this operation, if any.
local ConstructionOperation = class("things.ConstructionOperation", Operation)
lib.ConstructionOperation = ConstructionOperation

---@param entity LuaEntity A *valid* entity.
---@param tags? Tags
---@param player? LuaPlayer
function ConstructionOperation:new(entity, tags, player)
	local obj = Operation.new(self, "construction", entity) --[[@as things.ConstructionOperation ]]
	obj.is_ghost = entity.type == "entity-ghost"
	if player then
		obj.player = player
		obj.player_index = player.index
		local prebuild_state = get_prebuild_player_state(player.index)
		if prebuild_state and prebuild_state:was_key_prebuilt(obj.key) then
			obj.prebuilt = true
		end
	end
	if tags then
		obj.tags = tags --[[@as Tags]]
		obj.local_id = tags[LOCAL_ID_TAG] --[[@as integer? ]]
	end

	return obj
end

return lib
