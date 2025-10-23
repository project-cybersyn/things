-- Op for when a player initiates undo during a frame.

local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ur_util = require("control.util.undo-redo")
local strace = require("lib.core.strace")
local ws_lib = require("lib.core.world-state")

local Op = op_lib.Op
local OpType = op_lib.OpType
local UNDO = OpType.UNDO
local make_world_key = ws_lib.make_world_key

local lib = {}

---@class things.UndoOp: things.Op
---@field public actions {[int]: UndoRedoAction} The list of actions that were undone.
---@field public undo_opset_id int64?
---@field public redo_opset_id int64?
local UndoOp = class("things.UndoOp", op_lib.Op)
lib.UndoOp = UndoOp

---@param player_index int The index of the player who initiated the undo.
---@param actions {[int]: UndoRedoAction} The list of actions that were undone.
function UndoOp:new(player_index, actions)
	local obj = Op.new(self, UNDO) --[[@as things.UndoOp]]
	obj.player_index = player_index
	obj.actions = actions
	local undo_opset_id, redo_opset_id =
		ur_util.get_undo_opset_ids(nil, nil, actions)
	obj.undo_opset_id = undo_opset_id
	obj.redo_opset_id = redo_opset_id
	return obj
end

function UndoOp:catalogue(frame)
	if not self.undo_opset_id then
		strace.warn(
			frame.debug_string,
			"UndoOp:catalogue for player",
			self.player_index,
			"no undo_opset_id; skipping"
		)
		return
	end
	local opset = storage.stored_opsets[self.undo_opset_id]
	if not opset then
		strace.warn(
			frame.debug_string,
			"UndoOp:catalogue for player",
			self.player_index,
			"no opset found for undo_opset_id",
			self.undo_opset_id
		)
		return
	end
	strace.debug(
		frame.debug_string,
		"UndoOp:catalogue for player",
		self.player_index,
		"cataloguing undo opset",
		self.undo_opset_id
	)
	-- Match undone actions to the undo opset.
	for _, action in pairs(self.actions) do
		self:catalogue_action(frame, action, opset)
	end
end

---@param frame things.Frame
---@param action UndoRedoAction
---@param undo_op_set things.OpSet
function UndoOp:catalogue_action(frame, action, undo_op_set)
	local player_index = self.player_index
	if action.type == "removed-entity" then
		-- Match removal action to a CREATE op on this frame and a DESTROY or MFD
		-- op on the undo frame.

		---@cast action UndoRedoAction.removed_entity
		local removed_key = make_world_key(
			action.target.position,
			action.surface_index,
			action.target.name
		)
		local create_op = frame.op_set:findk_unique(
			removed_key,
			function(op)
				return (op.type == OpType.CREATE) and (op.player_index == player_index)
			end
		)
		if create_op then
			local destroy_op = undo_op_set:findk_unique(
				removed_key,
				function(op)
					return (op.type == OpType.DESTROY or op.type == OpType.MFD)
						and (op.player_index == player_index)
				end
			)
			if destroy_op then
				create_op.thing_id = destroy_op.thing_id
				strace.debug(
					frame.debug_string,
					"UndoOp:catalogue_action: matched remove-entity action for player",
					player_index,
					"at",
					create_op.key,
					"to Thing",
					create_op.thing_id
				)
			else
				strace.debug("no_destroy_match")
			end
		else
			strace.debug("no_create_match")
		end
	end
end

return lib
