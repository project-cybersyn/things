local pairs = pairs
local constants = require("control.constants")
local UNDO_TAG = constants.UNDO_TAG
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG

local lib = {}

---@param view? Core.UndoRedoStackView
---@param i? int Index of the undo/redo stack item
---@param actions {[int]: UndoRedoAction}
---@return int64|nil #The undo opset tag, if any
---@return int64|nil #The redo opset tag, if any
function lib.get_undo_opset_ids(view, i, actions)
	for j, action in pairs(actions) do
		local tag
		if view and i then
			tag = view.get_tag(i, j, UNDO_TAG)
		else
			tag = action.tags and action.tags[UNDO_TAG]
		end
		if tag then return tag[1], tag[2] end
	end
	return nil, nil
end

---@param view Core.UndoRedoStackView
---@param i int Index of the undo/redo stack item
---@param actions {[int]: UndoRedoAction}
---@param undo_opset_id int64|nil The stored undo opset id
---@param redo_opset_id int64|nil The stored redo opset id
function lib.set_undo_opset_ids(view, i, actions, undo_opset_id, redo_opset_id)
	if undo_opset_id or redo_opset_id then
		for j in pairs(actions) do
			view.set_tag(i, j, UNDO_TAG, { undo_opset_id, redo_opset_id })
			view.remove_tag(i, j, GHOST_REVIVAL_TAG)
		end
	else
		for j in pairs(actions) do
			view.remove_tag(i, j, UNDO_TAG)
			view.remove_tag(i, j, GHOST_REVIVAL_TAG)
		end
	end
end

return lib
