-- Things API.

local type = _G.type

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

---Makes `entity` a Thing.
---@param entity LuaEntity
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean? created True if a new Thing was created, false if the entity was already a Thing.
---@return int? thing_id The thing_id of the existing or newly created Thing.
function remote_interface.thingify(entity)
	if (not entity) or not entity.valid or not entity.unit_number then
		return CANT_BE_A_THING
	end
	local created, thing = thingify_entity(entity)
	if thing then
		return nil, created, thing.id
	else
		-- This should never happen
		return UNKNOWN
	end
end

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
