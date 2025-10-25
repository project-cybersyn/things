-- Parent op
local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local strace = require("lib.core.strace")

local lib = {}
---@class things.ParentOp: things.Op
---@field public child_thing_id int64? The ID of the child Thing.
---@field public parent_thing_id int64? The ID of the parent Thing.
---@field public child_index string|int Child key in parent
---@field public relative_position? MapPosition Relative position of child to parent
---@field public relative_orientation? Core.Orientation Relative orientation of child to parent
local ParentOp = class("things.ParentOp", op_lib.Op)
lib.ParentOp = ParentOp

---@param child_key Core.WorldKey
---@param parent_key Core.WorldKey
---@param child_index string|int Child key in parent
---@param relative_position? MapPosition Relative position of child to parent
---@param relative_orientation? Core.Orientation Relative orientation of child to parent
function ParentOp:new(
	child_key,
	parent_key,
	child_index,
	relative_position,
	relative_orientation
)
	local obj = op_lib.Op.new(self, op_lib.OpType.PARENT, child_key) --[[@as things.ParentOp]]
	obj.secondary_key = parent_key
	obj.child_index = child_index
	obj.relative_position = relative_position
	obj.relative_orientation = relative_orientation
	return obj
end

function ParentOp:dehydrate_for_undo()
	-- Discard unresolved parents
	if (not self.child_thing_id) or not self.parent_thing_id then return false end
	return true
end

function ParentOp:apply(frame)
	local _, child_thing = frame:get_resolved(self.key)
	local _, parent_thing = frame:get_resolved(self.secondary_key)
	if child_thing and parent_thing then
		self.child_thing_id = child_thing.id
		self.parent_thing_id = parent_thing.id
		parent_thing:add_child(
			self.child_index,
			child_thing,
			self.relative_position,
			self.relative_orientation
		)
	else
		strace.warn(
			frame.debug_string,
			"ParentOp.apply: could not resolve child or parent Thing:",
			self.child_thing_id,
			self.parent_thing_id
		)
	end
end

return lib
