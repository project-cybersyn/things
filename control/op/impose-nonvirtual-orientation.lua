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
local IMPOSE_NONVIRTUAL_ORIENTATION =
	op_lib.OpType.IMPOSE_NONVIRTUAL_ORIENTATION

local lib = {}

---@class things.ImposeNonvirtualOrientationOp: things.Op
---@field entity? LuaEntity Originally-detected overlapping entity. (May be invalid after construction frame completes; must be checked.)
---@field key Core.WorldKey World key of the overlap.
---@field overlapped_orientation Core.Orientation The previous orientation. Used for undo/redo.
---@field imposed_orientation Core.Orientation Orientation imposed on the overlapped Thing
---@field skip true? `true` if the overlap is to be skipped due to invalidity or consolidation.
local ImposeNonvirtualOrientationOp =
	class("things.ImposeNonvirtualOrientationOp", op_lib.Op)
lib.ImposeNonvirtualOrientationOp = ImposeNonvirtualOrientationOp

---@param player_index int?
---@param entity LuaEntity
---@param key Core.WorldKey
---@param overlapped_thing_id int64
---@param overlapped_orientation Core.Orientation
---@param imposed_orientation Core.Orientation
function ImposeNonvirtualOrientationOp:new(
	player_index,
	entity,

	key,
	overlapped_thing_id,
	overlapped_orientation,
	imposed_orientation
)
	local obj = op_lib.Op.new(self, IMPOSE_NONVIRTUAL_ORIENTATION, key) --[[@as things.ImposeNonvirtualOrientationOp]]
	obj.player_index = player_index
	obj.entity = entity
	obj.thing_id = overlapped_thing_id
	obj.overlapped_orientation = overlapped_orientation
	obj.imposed_orientation = imposed_orientation
	return obj
end

function ImposeNonvirtualOrientationOp:catalogue(frame)
	if self.skip then return end
	local overlapped = self.entity

	if
		not overlapped
		or not overlapped.valid
		or (overlapped.status == defines.entity_status.marked_for_deconstruction)
	then
		self.skip = true
		strace.debug(
			frame.debug_string,
			"ImposeNonvirtualOrientationOp:catalogue: overlapped entity is invalid or marked for deconstruction; skipping"
		)
		return
	end

	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then
		self.skip = true
		strace.warn(
			frame.debug_string,
			"ImposeNonvirtualOrientationOp:catalogue: no Thing found for overlapped entity; skipping"
		)
		return
	end
end

function ImposeNonvirtualOrientationOp:apply(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)

	if not overlapped_thing then
		error(
			"ImposeNonvirtualOrientationOp:apply: Thing found in catalogue phase is missing in apply phase. This should be impossible and indicates an event order leak somewhere."
		)
	end

	overlapped_thing:inject_orientation_changed_event(self.overlapped_orientation)
end

function ImposeNonvirtualOrientationOp:apply_undo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	overlapped_thing:inject_orientation_changed_event(self.imposed_orientation)
end

function ImposeNonvirtualOrientationOp:apply_redo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	overlapped_thing:inject_orientation_changed_event(self.overlapped_orientation)
end

function ImposeNonvirtualOrientationOp:dehydrate_for_undo()
	if self.skip then return false end
	self.entity = nil
	return true
end

return lib
