-- Op for when a player initiates undo or redo during a frame.

local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ur_util = require("control.util.undo-redo")
local strace = require("lib.core.strace")
local ws_lib = require("lib.core.world-state")

local Op = op_lib.Op
local OpType = op_lib.OpType
local UNDO = OpType.UNDO
local REDO = OpType.REDO
local make_world_key = ws_lib.make_world_key

local lib = {}

---@class things.UndoRedoOp: things.Op
---@field public actions {[int]: UndoRedoAction} The list of actions that were undone. Note that this may be sparse.
---@field public opset_id int64?
---@field public inverse_opset_id int64?
local UndoRedoOp = class("things.UndoRedoOp", op_lib.Op)
lib.UndoRedoOp = UndoRedoOp

---@param type things.OpType
---@param player_index int The index of the player who initiated the op.
---@param actions {[int]: UndoRedoAction} The list of actions.
function UndoRedoOp:new(type, player_index, actions)
	local obj = Op.new(self, type) --[[@as things.UndoRedoOp]]
	obj.player_index = player_index
	obj.actions = actions
	local _, opset_id, inverse_opset_id =
		ur_util.get_undo_opset_ids(nil, nil, actions)
	obj.opset_id = opset_id
	obj.inverse_opset_id = inverse_opset_id
	return obj
end

function UndoRedoOp:catalogue(frame)
	if not self.opset_id then
		strace.warn(
			frame.debug_string,
			"UndoRedoOp:catalogue for player",
			self.player_index,
			"no opset_id; skipping"
		)
		return
	end
	local opset = storage.stored_opsets[self.opset_id]
	if not opset then
		strace.warn(
			frame.debug_string,
			"UndoRedoOp:catalogue for player",
			self.player_index,
			"no opset found for opset_id",
			self.opset_id
		)
		return
	end
	strace.debug(
		frame.debug_string,
		"UndoRedoOp:catalogue for player",
		self.player_index,
		"cataloguing opset",
		self.opset_id
	)
	-- Match undone actions to the undo opset.
	for _, action in pairs(self.actions) do
		self:catalogue_action(frame, action, opset)
	end
end

---@param frame things.Frame
---@param action UndoRedoAction
---@param opset things.OpSet
function UndoRedoOp:catalogue_action(frame, action, opset)
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
			local destroy_op = opset:findk_unique(
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
					"UndoRedoOp:catalogue_action: matched remove-entity action for player",
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

---@class things.UndoOp: things.UndoRedoOp
local UndoOp = class("things.UndoOp", UndoRedoOp)
lib.UndoOp = UndoOp

---@param player_index int The index of the player who initiated the op.
---@param actions {[int]: UndoRedoAction} The list of actions.
function UndoOp:new(player_index, actions)
	local obj = UndoRedoOp.new(self, UNDO, player_index, actions) --[[@as things.UndoOp]]
	return obj
end

---@class things.RedoOp: things.UndoRedoOp
local RedoOp = class("things.RedoOp", UndoRedoOp)
lib.RedoOp = RedoOp

---@param player_index int The index of the player who initiated the op.
---@param actions {[int]: UndoRedoAction} The list of actions.
function RedoOp:new(player_index, actions)
	local obj = UndoRedoOp.new(self, REDO, player_index, actions) --[[@as things.RedoOp]]
	return obj
end

return lib
