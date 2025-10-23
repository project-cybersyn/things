-- Overlap op

local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")
local oclass_lib = require("lib.core.orientation.orientation-class")
local orientation_lib = require("lib.core.orientation.orientation")
local tlib = require("lib.core.table")

local get_by_id = thing_lib.get_by_id
local o_stringify = orientation_lib.stringify
local o_loose_eq = orientation_lib.loose_eq
local OVERLAP = op_lib.OpType.OVERLAP

local lib = {}

---@class things.OverlapOp: things.Op
---@field entity? LuaEntity Originally-detected overlapping entity. (May be invalid after construction frame completes; must be checked.)
---@field pos MapPosition Position of the overlap.
---@field key Core.WorldKey World key of the overlap.
---@field overlapped_tags Tags? Tags of the overlapped Thing, if any.
---@field previous_orientation Core.Orientation? If an orientation was imposed, the previous orientation. Used for undo/redo.
---@field imposed_tags Tags? Tags imposed on the overlapped Thing, if any.
---@field imposed_orientation Core.Orientation? Orientation imposed on the overlapped Thing, if any.
---@field skip true? `true` if the overlap is to be skipped due to invalidity or consolidation.
local OverlapOp = class("things.OverlapOp", op_lib.Op)
lib.OverlapOp = OverlapOp

---@param player_index int
---@param entity LuaEntity
---@param name string Prototype name of the entity.
---@param pos MapPosition
---@param key Core.WorldKey
---@param overlapped_thing_id int64
---@param overlapped_tags Tags?
---@param imposed_tags Tags?
---@param imposed_orientation Core.Orientation?
function OverlapOp:new(
	player_index,
	entity,
	name,
	pos,
	key,
	overlapped_thing_id,
	overlapped_tags,
	imposed_tags,
	imposed_orientation
)
	local obj = op_lib.Op.new(self, OVERLAP, key) --[[@as things.OverlapOp]]
	obj.player_index = player_index
	obj.entity = entity
	obj.name = name
	obj.pos = pos
	obj.thing_id = overlapped_thing_id
	if overlapped_tags then
		obj.overlapped_tags = tlib.deep_copy(overlapped_tags)
	end
	if imposed_tags then obj.imposed_tags = tlib.deep_copy(imposed_tags) end
	obj.imposed_orientation = imposed_orientation
	return obj
end

function OverlapOp:catalogue(frame)
	if self.skip then return end
	local overlapped = self.entity

	if
		not overlapped
		or not overlapped.valid
		or (overlapped.status == defines.entity_status.marked_for_deconstruction)
	then
		strace.debug(
			frame.debug_string,
			"OverlapOp:catalogue: overlapped entity is invalid or marked for deconstruction; skipping"
		)
		return
	end

	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then
		self.skip = true
		strace.warn(
			frame.debug_string,
			"OverlapOp:catalogue: no Thing found for overlapped entity; skipping"
		)
		return
	end
	local current_orientation = overlapped_thing:get_orientation()
	if not current_orientation then
		self.skip = true
		strace.warn(
			frame.debug_string,
			"OverlapOp:catalogue: overlapped Thing has no orientation; skipping"
		)
		return
	end
	self.previous_orientation = current_orientation
	frame:mark_resolved(self.key, overlapped_thing)
end

function OverlapOp:apply(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	local current_orientation = self.previous_orientation
	if not overlapped_thing then
		error(
			"OverlapOp:apply: Thing found in catalogue phase is missing in apply phase. This should be impossible and indicates an event order leak somewhere."
		)
	end
	-- Impose tags
	overlapped_thing:set_tags(self.imposed_tags, true)

	-- Impose orientation
	if self.imposed_orientation then
		if not o_loose_eq(current_orientation, self.imposed_orientation) then
			self.previous_orientation = current_orientation
			overlapped_thing:set_orientation(self.imposed_orientation, true)
			frame:post_event(
				"things.thing_orientation_changed",
				overlapped_thing,
				self.imposed_orientation,
				current_orientation
			)
		end
	end
end

function OverlapOp:dehydrate_for_undo()
	if self.skip then return false end
	self.entity = nil
	return true
end

---@param opset things.OpSet
function lib.consolidate_overlap_ops(opset)
	local by_key = opset.by_key
	for key, ops in pairs(by_key) do
		local first_overlap_op, last_overlap_op
		local n_overlap_ops = 0
		for i = 1, #ops do
			local op = ops[i]
			if op.type == OVERLAP then
				n_overlap_ops = n_overlap_ops + 1
				if not first_overlap_op then first_overlap_op = op end
				last_overlap_op = op
			end
		end
		if
			first_overlap_op
			and last_overlap_op
			and first_overlap_op ~= last_overlap_op
		then
			-- Consolidate into first op.
			strace.debug(
				"Consolidating ",
				n_overlap_ops,
				" overlap ops for key ",
				key,
				" into first op."
			)
			first_overlap_op.imposed_tags = last_overlap_op.imposed_tags
			first_overlap_op.imposed_orientation = last_overlap_op.imposed_orientation
			-- Remove other overlap ops.
			for i = 1, #ops do
				local op = ops[i]
				if op.type == OVERLAP and op ~= first_overlap_op then
					---@cast op things.OverlapOp
					op.skip = true
				end
			end
		end
	end
end

return lib
