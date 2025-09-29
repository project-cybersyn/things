local class = require("lib.core.class").class

local EMPTY = setmetatable({}, { __newindex = function() end })

---A simple graph on Things.
---@class things.Graph
---@field public name string The name of this graph. Unique throughout the game state.
---@field public edges {[int]: {[int]: things.GraphEdge}} Map of Thing id to set of edges that Thing is connected to.
local Graph = class("things.Graph")
_G.Graph = Graph

function Graph:new(name)
	local obj = setmetatable({
		name = name,
		edges = {},
	}, self)
	storage.graphs[name] = obj
	return obj
end

function Graph:destroy() storage.graphs[self.name] = nil end

---@param id1 int
---@param id2 int
---@return things.GraphEdge?
function Graph:get_edge(id1, id2)
	local edges = self.edges
	return edges[id1] and edges[id1][id2] or nil
end

function Graph:get_edges(id1)
	local edges = self.edges
	return edges[id1] or EMPTY
end

---@param id1 int
---@param id2 int
---@return boolean created True if the edge was created, false if it already existed.
---@return things.GraphEdge edge The existing or newly created edge.
function Graph:add_edge(id1, id2)
	if id1 == id2 then error("Graph:add_edge: cannot create self-loop") end
	if id1 > id2 then
		id1, id2 = id2, id1
	end
	local edges = self.edges
	edges[id1] = edges[id1] or {}
	local edge = edges[id1][id2]
	if edge then return false, edge end
	edge = { first = id1, second = id2 }
	edges[id2] = edges[id2] or {}
	edges[id1][id2] = edge
	edges[id2][id1] = edge
	return true, edge
end

---@param id1 int
---@param id2 int
---@return things.GraphEdge? edge The removed edge, or nil if no edge existed.
---@return boolean isolated_1 True if the first Thing is now isolated (has no edges), false otherwise.
---@return boolean isolated_2 True if the second Thing is now isolated (has no edges), false otherwise.
function Graph:remove_edge(id1, id2)
	local edges = self.edges
	local edges_from_id1 = edges[id1]
	if not edges_from_id1 then return nil, false, false end
	local edges_from_id2 = edges[id2]
	if not edges_from_id2 then return nil, false, false end
	local edge = edges_from_id1[id2]
	edges_from_id1[id2] = nil
	edges_from_id2[id1] = nil
	if not edge then return nil, false, false end
	local isolated_1 = next(edges_from_id1) == nil
	local isolated_2 = next(edges_from_id2) == nil
	if isolated_1 then edges[id1] = nil end
	if isolated_2 then edges[id2] = nil end
	return edge, isolated_1, isolated_2
end

---@param name string
---@return things.Graph
function _G.get_or_create_graph(name)
	local graph = storage.graphs[name]
	if not graph then graph = Graph:new(name) end
	return graph
end

---@param name string
---@return things.Graph?
function _G.get_graph(name) return storage.graphs[name] end
