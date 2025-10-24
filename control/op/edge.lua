-- Create edge op
local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local op_lib = require("control.op.op")

local lib = {}

---@class things.CreateEdgeOp: things.Op
---@field public source_thing_id int64? The ID of the first Thing in the edge.
---@field public target_thing_id int64? The ID of the second Thing in the edge.
---@field public name string The name of the graph the edge belongs to.
---@field public data Tags? Optional user data associated with this edge.
local CreateEdgeOp = class("things.CreateEdgeOp", op_lib.Op)
lib.CreateEdgeOp = CreateEdgeOp

---@param source_key Core.WorldKey The world key of the first Thing in the edge.
---@param target_key Core.WorldKey The world key of the second Thing in the edge.
---@param name string The name of the graph the edge belongs to.
---@param data? Tags Optional user data associated with this edge.
function CreateEdgeOp:new(source_key, target_key, name, data)
	local obj = op_lib.Op.new(self, op_lib.OpType.CREATE_EDGE, source_key) --[[@as things.CreateEdgeOp]]
	obj.secondary_key = target_key
	obj.name = name
	if data then obj.data = tlib.deep_copy(data) end
	return obj
end

function CreateEdgeOp:dehydrate_for_undo()
	-- Discard unresolved edges
	if (not self.source_thing_id) or not self.target_thing_id then
		return false
	end
	return true
end

function CreateEdgeOp:apply(frame)
	local _, source_thing = frame:get_resolved(self.key)
	local _, target_thing = frame:get_resolved(self.secondary_key)
	if source_thing and target_thing then
		-- TODO: Create the graph if needed
		-- TODO: Create the edge in the graph
		-- TODO: schedule event
	end
end

return lib
