-- Individual operations within a construction frame.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local ws_lib = require("lib.core.world-state")

local get_world_state = ws_lib.get_world_state

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
	ORIENTATION = 6,
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
	"CREATE",
	"MFD",
	"TAGS",
	"CREATE_EDGE",
	"PARENT",
	"ORIENTATION",
	"DESTROY",
	"BLUEPRINT",
	"UNDO",
	"REDO",
	"OVERLAP",
}
lib.OpType = OpType

---@class things.Op: Core.PartialWorldState
---@field public type things.OpType The type of this operation.
---@field public player_index? uint The index of the player who initiated this operation, if any.
---@field public thing_id? uint64 The ID of the Thing this operation applies to, if any.
---@field public local_id? string A local ID for this operation, if any. Used to correlate operations before Thing IDs are assigned.
local Op = class("things.Op")
lib.Op = Op

---@param type things.OpType
---@param world_state_or_key? Core.PartialWorldState|Core.WorldState|Core.WorldKey
function Op:new(type, world_state_or_key)
	local obj
	if type(world_state_or_key) == "string" then
		obj = { key = world_state_or_key, type = type }
	else
		obj = tlib.assign({}, world_state_or_key) --[[@as things.Op]]
		obj.type = type
	end
	setmetatable(obj, self)
	return obj
end

---Dehydrate this operation for long term storage attached to an undo record.
---This involves discarding any transient info. This function should also
---return `true` or `false` indicating whether the operation should be retained
---at all. Returning `false` indicates the operation is transient and drops it altogether.
function Op:dehydrate_for_undo() return true end

function Op:destroy() end

--------------------------------------------------------------------------------
-- CREATE ENTITY OP
--------------------------------------------------------------------------------

---@class things.CreateOp: things.Op
---@field public entity LuaEntity The entity created by this operation
---@field public tags? Tags Initial tags to set on the created Thing.
---@field public needs_init true? Whether a deferred initialization event should be broadcast for this operation.
local CreateOp = class("things.CreateOp", Op)
lib.CreateOp = CreateOp

---@param entity LuaEntity A *valid* entity.
---@param world_state? Core.WorldState The world state of the created entity. If omitted, it will be generated from the entity.
function CreateOp:new(entity, world_state)
	if not world_state then world_state = get_world_state(entity) end
	local obj = Op.new(self, OpType.CREATE, world_state) --[[@as things.CreateOp]]
	obj.entity = entity
	return obj
end

function CreateOp:dehydrate_for_undo()
	if self.tags then
		-- Redo operations will need the tags to recreate the Thing properly.
		self.entity = nil
		return true
	else
		-- Create ops without tags can be safely discarded.
		return false
	end
end

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

return lib
