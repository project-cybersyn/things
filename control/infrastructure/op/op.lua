-- Individual operations within a construction frame.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")

local lib = {}

---@class things.Op: Core.WorldState
---@field public type string The type of this operation.
---@field public player_index? uint The index of the player who initiated this operation, if any.
local Op = class("things.Op")
lib.Op = Op

function Op:new(type, world_state)
	local obj = tlib.assign({}, world_state) --[[@as things.Op]]
	obj.type = type
	setmetatable(obj, self)
	return obj
end

function Op:destroy() end

return lib
