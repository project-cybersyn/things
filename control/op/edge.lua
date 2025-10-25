-- Create edge op
local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local op_lib = require("control.op.op")
local graph_lib = require("control.graph")
local strace = require("lib.core.strace")

local lib = {}

---@class things.CreateEdgeOp: things.Op
---@field public from_thing_id int64? The ID of the first Thing in the edge.
---@field public to_thing_id int64? The ID of the second Thing in the edge.
---@field public was_created boolean? True if the edge was created when applying this op.
---@field public name string The name of the graph the edge belongs to.
---@field public data Tags? Optional user data associated with this edge.
local CreateEdgeOp = class("things.CreateEdgeOp", op_lib.Op)
lib.CreateEdgeOp = CreateEdgeOp

---@param player_index uint? The player index performing the operation.
---@param from_key Core.WorldKey The world key of the first Thing in the edge.
---@param to_key Core.WorldKey The world key of the second Thing in the edge.
---@param name string The name of the graph the edge belongs to.
---@param data? Tags Optional user data associated with this edge.
function CreateEdgeOp:new(player_index, from_key, to_key, name, data)
	local obj = op_lib.Op.new(self, op_lib.OpType.CREATE_EDGE, from_key) --[[@as things.CreateEdgeOp]]
	obj.player_index = player_index
	obj.secondary_key = to_key
	obj.name = name
	if data then obj.data = tlib.deep_copy(data) end
	return obj
end

function CreateEdgeOp:dehydrate_for_undo()
	-- Discard unresolved edges
	if not self.from_thing_id or not self.to_thing_id or not self.was_created then
		return false
	end
	return true
end

function CreateEdgeOp:apply(frame)
	local graph = graph_lib.get_graph(self.name)
	if not graph then
		strace.warn(
			frame.debug_string,
			"CreateEdgeOp.apply: Graph not found:",
			self.name
		)
		return
	end
	local _, from_thing = frame:get_resolved(self.key)
	local _, to_thing = frame:get_resolved(self.secondary_key)
	if from_thing and to_thing then
		self.from_thing_id = from_thing.id
		self.to_thing_id = to_thing.id
		self.was_created = graph_lib.connect(graph, from_thing, to_thing, self.data)
	end
end

function CreateEdgeOp:apply_undo(frame)
	local graph = graph_lib.get_graph(self.name)
	if not graph then return end
	local from_thing = get_thing_by_id(self.from_thing_id)
	local to_thing = get_thing_by_id(self.to_thing_id)
	strace.trace(
		"CreateEdgeOp:apply_undo: removing edge from Thing",
		self.from_thing_id,
		"to Thing",
		self.to_thing_id,
		"in graph",
		self.name
	)
	if from_thing and to_thing then
		graph_lib.disconnect(graph, from_thing, to_thing)
	end
end

function CreateEdgeOp:apply_redo(frame)
	local graph = graph_lib.get_graph(self.name)
	if not graph then return end
	local from_thing = get_thing_by_id(self.from_thing_id)
	local to_thing = get_thing_by_id(self.to_thing_id)
	strace.trace(
		"CreateEdgeOp:apply_redo: adding edge from Thing",
		self.from_thing_id,
		"to Thing",
		self.to_thing_id,
		"in graph",
		self.name
	)
	if from_thing and to_thing then
		graph_lib.connect(graph, from_thing, to_thing, self.data)
	end
end

return lib
