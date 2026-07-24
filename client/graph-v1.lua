local rcall = remote and remote.call

---@class things.client.GraphV1Lib
local lib = {}

---Get all graph edges emanating from a Thing in a given graph. For undirected
---graphs, both `out_edges` and `in_edges` are relevant and must be checked.
---@param graph_name string? The name of the graph to get edges from.
---@param thing_id things.Id? Id of the Thing to get edges for.
---@return table<int, things.GraphEdge>? out_edges Outgoing edges indexed by Thing ID on the other side of the edge. `nil` if the graph does not exist or the Thing is not in the graph.
---@return table<int, things.GraphEdge>? in_edges Incoming edges indexed by Thing ID on the other side of the edge. `nil` if the graph does not exist or the Thing is not in the graph.
function lib.get_edges(graph_name, thing_id)
	local _, out_edges, in_edges =
		rcall("things", "get_edges", graph_name, thing_id)
	---@cast out_edges table<int, things.GraphEdge>?
	---@cast in_edges table<int, things.GraphEdge>?
	return out_edges, in_edges
end

---Create an edge between two Things in a given graph.
---@param graph_name string The name of the graph to create the edge in.
---@param from_thing_id things.Id The ID of the Thing to create the edge from.
---@param to_thing_id things.Id The ID of the Thing to create the edge to.
---@param edge_data Tags? Additional data to associate with the edge.
---@return boolean success Whether the edge was successfully created. If false, the graph may not exist, or one of the Things may not be in the graph, or the edge may already be in the graph.
function lib.create_edge(graph_name, from_thing_id, to_thing_id, edge_data)
	local err = rcall(
		"things",
		"modify_edge",
		graph_name,
		"create",
		from_thing_id,
		to_thing_id,
		edge_data
	)
	if err then
		return false
	else
		return true
	end
end

---Delete an edge between two Things in a given graph.
---@param graph_name string The name of the graph to delete the edge from.
---@param from_thing_id things.Id The ID of the Thing to delete the edge from.
---@param to_thing_id things.Id The ID of the Thing to delete the edge to.
---@return boolean success Whether the edge was successfully deleted. If false, the graph may not exist, or one of the Things may not be in the graph, or the edge may not exist in the graph.
function lib.delete_edge(graph_name, from_thing_id, to_thing_id)
	local err = rcall(
		"things",
		"modify_edge",
		graph_name,
		"delete",
		from_thing_id,
		to_thing_id
	)
	if err then
		return false
	else
		return true
	end
end

---Toggle an edge between two Things in a given graph.
---@param graph_name string The name of the graph to toggle the edge in.
---@param from_thing_id things.Id The ID of the Thing to toggle the edge from.
---@param to_thing_id things.Id The ID of the Thing to toggle the edge to.
---@param edge_data Tags? Additional data to associate with the edge if it is created.
---@return boolean success Whether the edge was successfully toggled. If false, the graph may not exist, or one of the Things may not be in the graph.
function lib.toggle_edge(graph_name, from_thing_id, to_thing_id, edge_data)
	local err = rcall(
		"things",
		"modify_edge",
		graph_name,
		"toggle",
		from_thing_id,
		to_thing_id,
		edge_data
	)
	if err then
		return false
	else
		return true
	end
end

return lib
