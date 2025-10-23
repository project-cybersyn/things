-- Destroy op

local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")

local Op = op_lib.Op
local OpType = op_lib.OpType
local DESTROY = OpType.DESTROY
local get_world_state = ws_lib.get_world_state

local lib = {}

---@class things.DestroyOp: things.Op
local DestroyOp = class("things.DestroyOp", op_lib.Op)
lib.DestroyOp = DestroyOp

---@param entity LuaEntity The entity being destroyed.
---@param thing things.Thing The Thing being marked for deconstruction.
---@param player_index int? The index of the player who marked the entity for deconstruction.
function DestroyOp:new(entity, thing, player_index)
	local obj = Op.new(self, DESTROY, get_world_state(entity)) --[[@as things.DestroyOp]]
	obj.thing_id = thing.id
	obj.player_index = player_index
	return obj
end

function DestroyOp:dehydrate_for_undo()
	if self.player_index == nil then return false end
	return true
end

function DestroyOp:reconcile(frame)
	local thing = thing_lib.get_by_id(self.thing_id)
	if not thing then
		strace.warn(
			frame.debug_string,
			"DestroyOp:reconcile: no Thing found for destroyed entity; skipping",
			self.key
		)
		return
	end

	-- TODO: if thing is on the undo stack, tombstone it, otherwise destroy it
end

return lib
