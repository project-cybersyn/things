-- Op for when a player initiates redo during a frame.

local class = require("lib.core.class").class
local op_lib = require("control.op.op")

local Op = op_lib.Op
local OpType = op_lib.OpType
local REDO = OpType.REDO

local lib = {}

---@class things.RedoOp: things.Op
---@field public actions {[int]: UndoRedoAction} The list of actions that were redone.
local RedoOp = class("things.RedoOp", op_lib.Op)
lib.RedoOp = RedoOp

---@param player_index int The index of the player who initiated the redo.
---@param actions {[int]: UndoRedoAction} The list of actions that were redone.
function RedoOp:new(player_index, actions)
	local obj = Op.new(self, REDO) --[[@as things.RedoOp]]
	obj.player_index = player_index
	obj.actions = actions
	return obj
end

return lib
