-- Op for when a player initiates undo during a frame.

local class = require("lib.core.class").class
local op_lib = require("control.op.op")

local Op = op_lib.Op
local OpType = op_lib.OpType
local UNDO = OpType.UNDO

local lib = {}

---@class things.UndoOp: things.Op
---@field public actions {[int]: UndoRedoAction} The list of actions that were undone.
local UndoOp = class("things.UndoOp", op_lib.Op)
lib.UndoOp = UndoOp

---@param player_index int The index of the player who initiated the undo.
---@param actions {[int]: UndoRedoAction} The list of actions that were undone.
function UndoOp:new(player_index, actions)
	local obj = Op.new(self, UNDO) --[[@as things.UndoOp]]
	obj.player_index = player_index
	obj.actions = actions
	return obj
end

return lib
