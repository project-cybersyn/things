-- Individual operations within a construction frame.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")

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
---@param world_state Core.PartialWorldState|Core.WorldState
function Op:new(type, world_state)
	local obj = tlib.assign({}, world_state) --[[@as things.Op]]
	obj.type = type
	setmetatable(obj, self)
	return obj
end

function Op:destroy() end

return lib
