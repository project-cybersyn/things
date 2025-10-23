local events = require("lib.core.event")
local frame_lib = require("control.frame")

local UndoOp = require("control.op.undo-redo").UndoOp
local RedoOp = require("control.op.undo-redo").RedoOp

events.bind(
	defines.events.on_undo_applied,
	---@param event EventData.on_undo_applied
	function(event)
		local frame = frame_lib.get_frame()
		frame:add_op(UndoOp:new(event.player_index, event.actions))
	end
)

events.bind(
	defines.events.on_redo_applied,
	---@param event EventData.on_redo_applied
	function(event)
		local frame = frame_lib.get_frame()
		frame:add_op(RedoOp:new(event.player_index, event.actions))
	end
)
