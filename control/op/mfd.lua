-- MFD op

local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")

local Op = op_lib.Op
local OpType = op_lib.OpType
local MFD = OpType.MFD
local get_world_state = ws_lib.get_world_state

local lib = {}

---@class things.MfdOp: things.Op
---@field public entity LuaEntity The entity marked for deconstruction.
local MfdOp = class("things.MfdOp", op_lib.Op)
lib.MfdOp = MfdOp

---@param entity LuaEntity A *valid* entity.
---@param world_state? Core.WorldState The world state of the entity. If omitted, it will be generated from the entity.
---@param thing things.Thing The Thing being marked for deconstruction.
---@param player_index int? The index of the player who marked the entity for deconstruction.
function MfdOp:new(entity, world_state, thing, player_index)
	if not world_state then world_state = get_world_state(entity) end
	local obj = Op.new(self, MFD, world_state) --[[@as things.MfdOp]]
	obj.entity = entity
	obj.thing_id = thing.id
	obj.player_index = player_index
	return obj
end

function MfdOp:dehydrate_for_undo()
	self.entity = nil
	return true
end

return lib
