-- Parent op
local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local strace = require("lib.core.strace")
local tlib = require("lib.core.table")

local CREATE_OP = op_lib.OpType.CREATE

local lib = {}
---@class things.ParentOp: things.Op
---@field public child_thing_id int64? The ID of the child Thing.
---@field public parent_thing_id int64? The ID of the parent Thing.
---@field public child_index string Child key in parent
---@field public relative_position? MapPosition Relative position of child to parent
---@field public relative_orientation? Core.Orientation Relative orientation of child to parent
local ParentOp = class("things.ParentOp", op_lib.Op)
lib.ParentOp = ParentOp

---@param child_key Core.WorldKey
---@param parent_key Core.WorldKey
---@param child_index string Child key in parent
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
	-- Resolve child
	local child_key = self.key
	local _, child_thing, child_things = frame:get_resolved(child_key)

	-- Multiple ambiguous children
	if child_things then
		local op_set = frame.op_set
		local built_this_frame, preexisting = tlib.split(
			child_things,
			function(thing)
				local entity = thing.entity
				local create_op = op_set:findkt_first(child_key, CREATE_OP) --[[@as things.CreateOp?]]
				if not create_op then return false end
				return (entity == create_op.entity)
			end
		)
		-- TODO: If 1-1 mapping, consider additively transferring wires from the newly-built child to the old one.
		strace.error(
			frame.debug_string,
			"ParentOp.apply: multiple Things resolved to child key",
			child_key,
			"child_things:",
			child_things,
			"built_this_frame:",
			built_this_frame,
			"preexisting:",
			preexisting
		)
		strace.error(
			frame.debug_string,
			"Assuming pre-existing things are correct children and newly-built ones are orphans; snap-destroying the orphans."
		)
		tlib.for_each(built_this_frame, function(thing)
			thing.is_silent = true
			thing:destroy(false, true)
		end)
		return
	end

	if (not child_thing) or (not child_thing:is_valid()) then
		strace.warn(
			frame.debug_string,
			"ParentOp.apply: could not resolve child Thing:",
			self.key
		)
		return
	end
	strace.trace(
		frame.debug_string,
		"ParentOp.apply: resolved child Thing",
		child_thing.id,
		"at key",
		child_key
	)
	local child_was_built_this_frame
	do
		local create_op = frame.op_set:findkt_first(child_key, CREATE_OP) --[[@as things.CreateOp?]]
		child_was_built_this_frame = (
			create_op and create_op.entity == child_thing.entity
		)
	end

	-- Resolve parent
	local _, parent_thing = frame:get_resolved(self.secondary_key)
	if (not parent_thing) or (not parent_thing:is_valid()) then
		strace.warn(
			frame.debug_string,
			"ParentOp.apply: could not resolve parent Thing.",
			self.secondary_key
		)
		if child_was_built_this_frame then
			strace.warn(
				frame.debug_string,
				"ParentOp.apply: child Thing was built this frame, but parent Thing could not be resolved; snap-destroying child to avoid orphan.",
				child_thing.id
			)
			child_thing.is_silent = true
			child_thing:destroy(false, true)
		end
		return
	end

	-- Pre-existing children
	if parent_thing:has_child(self.child_index) then
		strace.warn(
			frame.debug_string,
			"ParentOp.apply: parent Thing already has child at index",
			self.child_index
		)
		if child_was_built_this_frame then
			strace.warn(
				frame.debug_string,
				"ParentOp.apply: child Thing was built this frame, but parent already has child at index; snap-destroying child to avoid orphan.",
				child_thing.id
			)
			child_thing.is_silent = true
			child_thing:destroy(false, true)
		end
		return
	end

	-- Create new relationship
	self.child_thing_id = child_thing.id
	self.parent_thing_id = parent_thing.id
	parent_thing:add_child(
		self.child_index,
		child_thing,
		self.relative_position,
		self.relative_orientation
	)
end

return lib
