-- Orientation-change operation

local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local orientation_lib = require("lib.core.orientation.orientation")
local strace = require("lib.core.strace")

local get_world_state = ws_lib.get_world_state
local Op = op_lib.Op
local ORIENTATION = op_lib.OpType.ORIENTATION
local o_loose_eq = orientation_lib.loose_eq

local lib = {}

---@class things.OrientationOp: things.Op
---@field public entity LuaEntity
---@field public previous_orientation? Core.Orientation
---@field public orientation Core.Orientation
local OrientationOp = class("things.OrientationOp", Op)
lib.OrientationOp = OrientationOp

---@param player_index int?
---@param entity LuaEntity
---@param thing_id? int64
---@param previous_orientation Core.Orientation?
---@param transform Core.Dihedral?
---@param next_orientation Core.Orientation?
---@param untransform Core.Dihedral?
function OrientationOp:new(
	player_index,
	entity,
	thing_id,
	previous_orientation,
	transform,
	next_orientation,
	untransform
)
	if (not previous_orientation) and not next_orientation then
		error("OrientationOp:new: Must provide previous or next orientation")
		return
	end
	if not next_orientation then
		if not transform then return nil end
		next_orientation = orientation_lib.apply(
			previous_orientation --[[@as Core.Orientation]],
			transform
		)
	end
	if not previous_orientation then
		if not untransform then return nil end
		previous_orientation = orientation_lib.apply(
			next_orientation --[[@as Core.Orientation]],
			untransform
		)
	end
	strace.trace(
		"New OrientationOp for Thing",
		thing_id,
		"from",
		orientation_lib.stringify(previous_orientation),
		"to",
		orientation_lib.stringify(next_orientation)
	)
	local obj = Op.new(self, ORIENTATION, get_world_state(entity)) --[[@as things.OrientationOp]]
	obj.player_index = player_index
	obj.previous_orientation = previous_orientation
	obj.orientation = next_orientation
	obj.thing_id = thing_id
	obj.entity = entity
	return obj
end

function OrientationOp:dehydrate_for_undo()
	self.entity = nil
	return true
end

function OrientationOp:apply(frame)
	local thing = get_thing_by_id(self.thing_id)
	if not thing then
		strace.debug(
			frame.debug_string,
			"OrientationOp:apply: Thing not found; skipping"
		)
		return
	end
	local current_orientation = thing:get_orientation()
	if not current_orientation then
		strace.debug(
			frame.debug_string,
			"OrientationOp:apply: Thing has no orientation; skipping"
		)
		return
	end
	if not self.previous_orientation then
		self.previous_orientation = current_orientation
	end
	local changed, imposed = thing:set_orientation(self.orientation, true, true)
	strace.trace(
		frame.debug_string,
		"OrientationOp:apply from",
		orientation_lib.stringify(self.previous_orientation),
		"to",
		orientation_lib.stringify(self.orientation),
		changed and "- Thing orientation changed" or "- Thing orientation unchanged",
		(not imposed) and "- entity was already at desired orientation"
			or "- orientation imposed on entity"
	)

	frame:post_event(
		"things.thing_orientation_changed",
		thing,
		self.orientation,
		self.previous_orientation
	)
end

return lib
