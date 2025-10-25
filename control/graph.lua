local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local EMPTY = tlib.EMPTY_STRICT
local reg_lib = require("control.registration")
local events = require("lib.core.event")
local strace = require("lib.core.strace")

local lib = {}

---A simple graph on integer nodes, representing Thing ids.
---@class things.Graph
---@field public name string The name of this graph. Unique throughout the game state.
---@field public is_directed boolean? Whether this graph is directed. When undirected, edges point from lower to higher id.
---@field public out_edges {[int]: {[int]: things.GraphEdge}} Map of id to set of edges that point away from that node.
---@field public in_edges {[int]: {[int]: things.GraphEdge}} Map of id to set of edges that point into that node.
local Graph = class("things.Graph")
lib.Graph = Graph

function Graph:new(name)
	local obj = setmetatable({
		name = name,
		out_edges = {},
		in_edges = {},
	}, self)
	storage.graphs[name] = obj
	return obj
end

function Graph:destroy() storage.graphs[self.name] = nil end

---Get the given directed edge, if it exists.
---@param from_id int64
---@param to_id int64
---@return things.GraphEdge?
function Graph:get_edge(from_id, to_id)
	local edges = self.out_edges
	if (not self.is_directed) and (from_id > to_id) then
		from_id, to_id = to_id, from_id
	end
	return edges[from_id] and edges[from_id][to_id] or nil
end

---Get all edges entering and leaving the given node.
---@param id int64
---@return {[int]: things.GraphEdge} out_edges
---@return {[int]: things.GraphEdge} in_edges
function Graph:get_edges(id)
	return self.out_edges[id] or EMPTY, self.in_edges[id] or EMPTY
end

---Add an edge, returning an existing edge if it already exists.
---@param from_id int
---@param to_id int
---@param data Tags? Additional data to store on the edge.
---@return boolean created True if the edge was created, false if it already existed.
---@return things.GraphEdge edge The existing or newly created edge.
function Graph:add_edge(from_id, to_id, data)
	if from_id == to_id then error("Graph:add_edge: cannot create self-loop") end
	if (not self.is_directed) and (from_id > to_id) then
		from_id, to_id = to_id, from_id
	end
	local out_edges = self.out_edges
	out_edges[from_id] = out_edges[from_id] or {}
	local edge = out_edges[from_id][to_id]
	if edge then return false, edge end
	edge = { from = from_id, to = to_id, data = data }
	out_edges[from_id][to_id] = edge
	local in_edges = self.in_edges
	in_edges[to_id] = in_edges[to_id] or {}
	in_edges[to_id][from_id] = edge
	return true, edge
end

---Remove an edge.
---@param from_id int
---@param to_id int
---@return things.GraphEdge? edge The removed edge, or nil if no edge existed.
function Graph:remove_edge(from_id, to_id)
	if from_id == to_id then return nil end
	if (not self.is_directed) and (from_id > to_id) then
		from_id, to_id = to_id, from_id
	end
	local out_edges = self.out_edges
	local in_edges = self.in_edges
	local edges_from_id1 = out_edges[from_id]
	if not edges_from_id1 then return nil end
	local edge = edges_from_id1[to_id]
	if not edge then return nil end
	edges_from_id1[to_id] = nil
	in_edges[to_id][from_id] = nil
	return edge
end

---Remove a vertex and all its associated edges.
---@param id int
function Graph:remove_vertex(id)
	local out_edges = self.out_edges[id]
	if out_edges then
		for to_id, _ in pairs(out_edges) do
			self.in_edges[to_id][id] = nil
		end
		self.out_edges[id] = nil
	end
	local in_edges = self.in_edges[id]
	if in_edges then
		for from_id, _ in pairs(in_edges) do
			self.out_edges[from_id][id] = nil
		end
		self.in_edges[id] = nil
	end
end

---@param name string
---@return things.Graph?
function lib.get_graph(name)
	local graph = storage.graphs[name]
	if graph then return graph end
	local reg = reg_lib.get_graph_registration(name)
	if not reg then return nil end
	graph = Graph:new(name)
	graph.is_directed = reg.directed
	return graph
end

---Get the set of all graph names containing the given node.
---@param id int
---@return {[string]: things.Graph} graph_set
function lib.get_graphs_containing_node(id)
	local result = nil
	for _, graph in pairs(storage.graphs) do
		local out_edges = graph.out_edges
		local in_edges = graph.in_edges
		if
			(out_edges[id] and next(out_edges[id]))
			or (in_edges[id] and next(in_edges[id]))
		then
			if not result then result = {} end
			result[graph.name] = graph
		end
	end
	return result or EMPTY
end

---Connect two Things in the given graph.
---@param graph things.Graph
---@param from things.Thing
---@param to things.Thing
---@param data Tags?
---@return boolean created True if the edge was created, false if it could not be.
function lib.connect(graph, from, to, data)
	if not graph or not from or not to then return false end
	if (not graph.is_directed) and (from.id > to.id) then
		from, to = to, from
	end
	local created, edge = graph:add_edge(from.id, to.id, data)
	if created then
		local frame = in_frame()
		if frame then
			frame:post_event("things.graph_add_edge", graph, edge, from, to)
		else
			events.raise("things.graph_add_edge", graph, edge, from, to)
		end
		return true
	end
	return false
end

---Disconnect two Things in the given graph.
---@param graph things.Graph
---@param from things.Thing
---@param to things.Thing
function lib.disconnect(graph, from, to)
	if not graph or not from or not to then return end
	if (not graph.is_directed) and (from.id > to.id) then
		from, to = to, from
	end
	local edge = graph:remove_edge(from.id, to.id)
	if edge then
		strace.debug("Graph", graph.name, "disconnected", from.id, "from", to.id)
		local frame = in_frame()
		if frame then
			frame:post_event("things.graph_remove_edge", graph, edge, from, to)
		else
			events.raise("things.graph_remove_edge", graph, edge, from, to)
		end
	end
end

---Set data on the given edge in a graph.
---@param graph things.Graph
---@param from things.Thing
---@param to things.Thing
---@param data Tags?
function lib.set_edge_data(graph, from, to, data)
	if not graph or not from or not to then return end
	if (not graph.is_directed) and (from.id > to.id) then
		from, to = to, from
	end
	local edge = graph:get_edge(from.id, to.id)
	if edge then
		edge.data = data
		local frame = in_frame()
		if frame then
			frame:post_event("things.graph_set_edge_data", graph, edge, from, to)
		else
			events.raise("things.graph_set_edge_data", graph, edge, from, to)
		end
	end
end

return lib
