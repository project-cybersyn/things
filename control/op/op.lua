-- Individual operations within a construction frame.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local ws_lib = require("lib.core.world-state")

local get_world_state = ws_lib.get_world_state
local type = type

local lib = {}

--------------------------------------------------------------------------------
-- GENERIC OP
--------------------------------------------------------------------------------

---Species of operations.
---@enum things.OpType
local OpType = {
	---Create a new Thing
	CREATE = 1,
	---Mark a Thing's main entity for destruction
	MFD = 2,
	---Set tags on a Thing
	TAGS = 3,
	---Create an edge in a graph
	CREATE_EDGE = 4,
	---Set the parent of a Thing
	PARENT = 5,
	---Set the orientation of a Thing
	IMPOSE_ORIENTATION = 6,
	---Completely destroy a Thing
	DESTROY = 7,
	---Player built a blueprint
	BLUEPRINT = 8,
	---Player undid an action
	UNDO = 9,
	---Player redid an action
	REDO = 10,
	---Generic marker for entity overlap.
	OVERLAP = 11,
	---Change thing orientation.
	ORIENTATION = 12,
	"CREATE",
	"MFD",
	"TAGS",
	"CREATE_EDGE",
	"PARENT",
	"IMPOSE_ORIENTATION",
	"DESTROY",
	"BLUEPRINT",
	"UNDO",
	"REDO",
	"OVERLAP",
	"ORIENTATION",
}
lib.OpType = OpType

---@class things.Op: Core.PartialWorldState
---@field public type things.OpType The type of this operation.
---@field public player_index? uint The index of the player who initiated this operation, if any.
---@field public thing_id? uint64 The ID of the Thing this operation applies to, if any.
---@field public local_id? string A local ID for this operation, if any. Used to correlate operations before Thing IDs are assigned.
---@field public secondary_key? Core.WorldKey A secondary world key for this operation, if any. Used for operations involving two Things.
local Op = class("things.Op")
lib.Op = Op

---@param ty things.OpType
---@param world_state_or_key? Core.PartialWorldState|Core.WorldState|Core.WorldKey
function Op:new(ty, world_state_or_key)
	local obj
	if type(world_state_or_key) == "string" then
		obj = { key = world_state_or_key, type = ty }
	else
		obj = tlib.assign({}, world_state_or_key) --[[@as things.Op]]
		obj.type = ty
	end
	setmetatable(obj, self)
	return obj
end

---Notify that a Thing was found at this op's key or secondary key.
---This can be used during op resolution to match ambiguous ops to Things.
---@param key Core.WorldKey The key at which the Thing was found.
---@param thing things.Thing The Thing found at the key.
function Op:resolved(key, thing) end

---Called for each op during the catalogue phase of a construction frame.
---@param frame things.Frame The current frame.
function Op:catalogue(frame) end

---Called for each op during the resolve phase of a construction frame.
---@param frame things.Frame The current frame.
function Op:resolve(frame) end

---Called for each op during the apply phase of a construction frame.
---@param frame things.Frame The current frame.
function Op:apply(frame) end

---Called for each op during the reconcile phase of a construction frame. Note
---that this takes place AFTER `dehydrate_for_undo` happens.
---@param frame things.Frame The current frame.
function Op:reconcile(frame) end

---Dehydrate this operation for long term storage attached to an undo record.
---This involves discarding any transient info. This function should also
---return `true` or `false` indicating whether the operation should be retained
---at all. Returning `false` indicates the operation is transient and drops it altogether.
function Op:dehydrate_for_undo() return false end

function Op:destroy() end

--------------------------------------------------------------------------------
-- SET TAGS OP
--------------------------------------------------------------------------------

---@class things.TagsOp: things.Op
---@field public previous_tags? Tags The previous tags on the Thing
---@field public tags Tags The new tags to be set on the Thing
local TagsOp = class("things.TagsOp", Op)
lib.TagsOp = TagsOp

---@param thing_id uint64 The ID of the Thing whose tags are being set.
---@param key Core.WorldKey The world key of the Thing whose tags are being set.
---@param tags Tags The new tags to set on the Thing.
---@param previous_tags? Tags The previous tags on the Thing, if any.
function TagsOp:new(thing_id, key, tags, previous_tags)
	local obj = Op.new(self, OpType.TAGS, key) --[[@as things.TagsOp]]
	obj.thing_id = thing_id
	obj.tags = tags
	obj.previous_tags = previous_tags
	return obj
end

--------------------------------------------------------------------------------
-- IMPOSE ORIENTATION OP
--------------------------------------------------------------------------------

---@class things.ImposeOrientationOp: things.Op
---@field public orientation Core.Orientation The new orientation to impose on the Thing.
---@field public prev_orientation Core.Orientation The previous orientation of the Thing.
local ImposeOrientationOp = class("things.ImposeOrientationOp", Op)
lib.ImposeOrientationOp = ImposeOrientationOp

---@param thing_id uint64 The ID of the Thing whose orientation is being imposed.
---@param key Core.WorldKey The world key of the Thing whose orientation is being imposed.
---@param orientation Core.Orientation The new orientation to impose on the Thing.
---@param prev_orientation Core.Orientation The previous orientation of the Thing.
function ImposeOrientationOp:new(thing_id, key, orientation, prev_orientation)
	local obj = Op.new(self, OpType.IMPOSE_ORIENTATION, key) --[[@as things.ImposeOrientationOp]]
	obj.thing_id = thing_id
	obj.orientation = orientation
	obj.prev_orientation = prev_orientation
	return obj
end

return lib
