-- Things API.

local type = _G.type
local EMPTY = {}

---@class (exact) things.Error
---@field public code string Machine-readable error code.
---@field public message LocalisedString Human-readable error message.

---Either the id of a Thing, or the LuaEntity currently representing it.
---@alias things.ThingIdentification int|LuaEntity

---@param identification things.ThingIdentification
---@return things.Thing? thing
---@return boolean valid_id
local function resolve_identification(identification)
	if type(identification) ~= "number" then
		if not identification.valid or not identification.unit_number then
			return nil, false
		end
		return get_thing_by_unit_number(identification.unit_number), true
	else
		return get_thing(identification), true
	end
end

---@type things.Error
local CANT_BE_A_THING = {
	code = "cant_be_a_thing",
	message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier.",
}

---@type things.Error
local NOT_A_THING = {
	code = "not_a_thing",
	message = "The specified Thing does not exist.",
}

---@type things.Error
local UNKNOWN = {
	code = "unknown",
	message = "An unknown error occurred.",
}

local remote_interface = {}
_G.remote_interface = remote_interface

---Gets basic status information about a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return int? thing_id The id of the Thing, or `nil` if the Thing doesn't exist.
---@return LuaEntity? entity The LuaEntity currently representing the Thing, or `nil` if no entity represents it.
---@return things.Status? status The status of the Thing.
function remote_interface.get_status(thing_identification)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return nil, nil, nil end
	return nil, thing.id, thing.entity, thing.state --[[@as things.Status]]
end

---Gets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return Tags? tags The tags of the Thing, or `nil` if the Thing doesn't exist.
function remote_interface.get_tags(thing_identification)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return nil, nil end
	return nil, thing.tags
end

---Sets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param tags Tags The new tags to set on the Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_tags(thing_identification, tags)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	thing:set_tags(tags)
	return nil
end

---Create a graph edge between two Things.
---@param graph_name string The name of the graph to create the edge in.
---@param thing_1 things.ThingIdentification One side of the edge.
---@param thing_2 things.ThingIdentification The other side of the edge.
---@param operation "create"|"delete"|"toggle"|"set-data"|nil The operation to perform on the edge. Defaults to "create".
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.modify_edge(
	graph_name,
	thing_1,
	thing_2,
	operation,
	data
)
	local thing1, valid_id1 = resolve_identification(thing_1)
	local thing2, valid_id2 = resolve_identification(thing_2)
	if not valid_id1 or not valid_id2 then return CANT_BE_A_THING end
	if not thing1 or not thing2 then return NOT_A_THING end
	local edge = thing1:graph_get_edge(graph_name, thing2)
	if operation == "create" then
		if edge then return nil end
		thing1:graph_connect(graph_name, thing2)
	elseif operation == "delete" then
		if not edge then return nil end
		thing1:graph_disconnect(graph_name, thing2)
	elseif operation == "toggle" then
		if edge then
			thing1:graph_disconnect(graph_name, thing2)
		else
			thing1:graph_connect(graph_name, thing2)
		end
	elseif operation == "set-data" then
		if not edge then return nil end
		-- TODO: impl
	end
	return nil
end

---Get all graph edges emanating from a Thing in a given graph.
---@param graph_name string The name of the graph to get edges from.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[int]: things.GraphEdge}|nil edges Edges indexed by destination Thing. `nil` if there was an error or the Thing doesn't exist. An empty object if the Thing has no edges in the graph.
function remote_interface.get_edges(graph_name, thing_identification)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local graph = get_graph(graph_name)
	if not graph then return nil, {} end
	local edges = graph:get_edges(thing.id)
	return nil, edges
end

---Adds a child Thing to a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_key string|int|nil The key to assign the child in the parent Thing. If `nil`, uses the smallest free numeric key as determined by the Lua `#` operator.
---@param child_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The child Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.add_child(
	parent_identification,
	child_key,
	child_identification
)
	local parent, valid_parent = resolve_identification(parent_identification)
	local child, valid_child = resolve_identification(child_identification)
	if not valid_parent or not valid_child then return CANT_BE_A_THING end
	if not parent or not child then return NOT_A_THING end
	if child_key == nil then child_key = #(parent.children or EMPTY) + 1 end
	local added = parent:add_child(child_key, child)
	if not added then
		return {
			code = "could_not_add_child",
			message = "Could not add child; the child may already have a parent, or the key may already be in use.",
		}
	end
	return nil
end

---Removes a child Thing from a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The child Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.remove_child(
	parent_identification,
	child_identification
)
	local parent, valid_parent = resolve_identification(parent_identification)
	local child, valid_child = resolve_identification(child_identification)
	if not valid_parent or not valid_child then return CANT_BE_A_THING end
	if not parent or not child then return NOT_A_THING end
	local removed = parent:remove_children(child)
	if (not removed) or (#removed == 0) then
		return {
			code = "could_not_remove_child",
			message = "Could not remove child; the specified Thing is not a child of the specified parent.",
		}
	end
	return nil
end

---Gets all children of a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[string|int]: int}|nil children Map of child keys to child Thing ids. `nil` if there was an error or the Thing doesn't exist. An empty object if the Thing has no children.
function remote_interface.get_children(parent_identification)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	local result = {}
	for key, child in pairs(parent.children or EMPTY) do
		result[key] = child.id
	end
	return nil, result
end
