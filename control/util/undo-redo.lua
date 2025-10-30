local pairs = pairs
local constants = require("control.constants")
local strace = require("lib.core.strace")
local UNDO_TAG = constants.UNDO_TAG
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG

local lib = {}

---@param view Core.UndoRedoStackView
---@param i int Index of the undo/redo stack item
---@return boolean #Whether the undo tag existed.
---@return int64|nil #The forward opset id. (undo if this is undo)
---@return int64|nil #The inverse opset id. (redo if this is undo)
function lib.fast_get_undo_opset_ids(view, i)
	local tag = view.get_tag(i, 1, UNDO_TAG)
	if tag then return true, tag[1], tag[2] end

	return false, nil, nil
end

---@param view? Core.UndoRedoStackView
---@param i? int Index of the undo/redo stack item
---@param actions {[int]: UndoRedoAction}
---@return boolean #Whether the undo tag existed.
---@return int64|nil #The forward opset id. (undo if this is undo)
---@return int64|nil #The inverse opset id. (redo if this is undo)
function lib.get_undo_opset_ids(view, i, actions)
	for j, action in pairs(actions) do
		local tag
		if view and i then
			tag = view.get_tag(i, j, UNDO_TAG)
		else
			tag = action.tags and action.tags[UNDO_TAG]
		end
		if tag then
			strace.log("Slowly found undo tag at", i, j, tag[1], tag[2])
			return true, tag[1], tag[2]
		end
	end
	return false, nil, nil
end

---@param view Core.UndoRedoStackView
---@param i int Index of the undo/redo stack item
---@param actions {[int]: UndoRedoAction}
---@param opset_id int64|nil The forward opset id (undo if this is undo)
---@param inverse_opset_id int64|nil The inverse opset id (redo if this is undo)
function lib.tag_undo_item(view, i, actions, opset_id, inverse_opset_id)
	for j in pairs(actions) do
		view.set_tag(i, j, UNDO_TAG, { opset_id, inverse_opset_id })
		view.remove_tag(i, j, GHOST_REVIVAL_TAG)
	end
end

return lib
