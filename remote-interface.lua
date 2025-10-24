-- Things API.

require("types")

local pos_lib = require("lib.core.math.pos")
local thing_lib = require("control.thing")

local get_thing_by_unit_number = thing_lib.get_by_unit_number
local get_thing = thing_lib.get_by_id

local type = _G.type
local EMPTY = {}

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

---Gets basic information about a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingSummary? summary Summary of the Thing, or `nil` if the Thing doesn't exist.
function remote_interface.get(thing_identification)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if thing then
		return nil, thing:summarize()
	else
		return nil, nil
	end
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
---@return boolean? toggle_result If `operation` is "toggle", this will be `true` if the edge was created, or `false` if it was deleted. `nil` otherwise.
function remote_interface.modify_edge(
	graph_name,
	thing_1,
	thing_2,
	operation,
	data
)
	-- TODO: fix graph shit
	-- local thing1, valid_id1 = resolve_identification(thing_1)
	-- local thing2, valid_id2 = resolve_identification(thing_2)
	-- if not valid_id1 or not valid_id2 then return CANT_BE_A_THING end
	-- if not thing1 or not thing2 then return NOT_A_THING end
	-- local edge = thing1:graph_get_edge(graph_name, thing2)
	-- if operation == "create" then
	-- 	if edge then
	-- 		return { code = "edge_exists", message = "Edge already exists." }
	-- 	end
	-- 	thing1:graph_connect(graph_name, thing2)
	-- elseif operation == "delete" then
	-- 	if not edge then
	-- 		return { code = "edge_does_not_exist", message = "Edge does not exist." }
	-- 	end
	-- 	thing1:graph_disconnect(graph_name, thing2)
	-- elseif operation == "toggle" then
	-- 	if edge then
	-- 		thing1:graph_disconnect(graph_name, thing2)
	-- 		return nil, false
	-- 	else
	-- 		thing1:graph_connect(graph_name, thing2)
	-- 		return nil, true
	-- 	end
	-- elseif operation == "set-data" then
	-- 	if not edge then return nil end
	-- 	-- TODO: impl
	-- end
	return nil
end

---Get all graph edges emanating from a Thing in a given graph.
---@param graph_name string The name of the graph to get edges from.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[int]: things.GraphEdge}|nil edges Edges indexed by destination Thing. `nil` if there was an error or the Thing doesn't exist. An empty object if the Thing has no edges in the graph.
function remote_interface.get_edges(graph_name, thing_identification)
	-- TODO: fix this graph shit
	return nil, {}
	-- local thing, valid_id = resolve_identification(thing_identification)
	-- if not valid_id then return CANT_BE_A_THING end
	-- if not thing then return NOT_A_THING end
	-- local graph = get_graph(graph_name)
	-- if not graph then return nil, {} end
	-- local edges = graph:get_edges(thing.id)
	-- return nil, edges
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
	if not valid_parent then
		return {
			code = "cant_be_a_thing",
			message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier for the parent.",
		}
	end
	if not parent then
		return {
			code = "not_a_thing",
			message = "The specified parent Thing does not exist.",
		}
	end
	if not valid_child then
		return {
			code = "cant_be_a_thing",
			message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier for the child.",
		}
	end
	if not child then
		return {
			code = "not_a_thing",
			message = "The specified child Thing does not exist.",
		}
	end
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
	-- TODO: fix this.
	-- local parent, valid_parent = resolve_identification(parent_identification)
	-- local child, valid_child = resolve_identification(child_identification)
	-- if not valid_parent or not valid_child then return CANT_BE_A_THING end
	-- if not parent or not child then return NOT_A_THING end
	-- local removed = parent:remove_children(child)
	-- if (not removed) or (#removed == 0) then
	-- 	return {
	-- 		code = "could_not_remove_child",
	-- 		message = "Could not remove child; the specified Thing is not a child of the specified parent.",
	-- 	}
	-- end
	return nil
end

---Gets all children of a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingChildrenSummary|nil children Map of child keys to child Thing summaries. `nil` if there was an error or the Thing doesn't exist. An empty object if the Thing has no children.
function remote_interface.get_children(parent_identification)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	local result = {}
	for key, child in pairs(parent.children or EMPTY) do
		local child_thing = get_thing(child)
		if child_thing then result[key] = child_thing:summarize() end
	end
	return nil, result
end

---Get transient data associated with a Thing. This data is not preserved when
---a thing is pasted, blueprinted, or overbuilt.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return Tags|nil transient_data The transient data associated with this Thing, if any.
function remote_interface.get_transient_data(thing_identification)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	return nil, thing.transient_data
end

---Attach transient data to a Thing. This data is not preserved when
---a thing is pasted, blueprinted, or overbuilt.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param key string The key to set in the transient data.
---@param value AnyBasic? The value to set in the transient data.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_transient_data(thing_identification, key, value)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	thing:set_transient_data(key, value)
	return nil
end

---Forcefully destroy a Thing and its underlying entity, if any.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param dont_destroy_entity boolean? If true, destroy the Thing but do not destroy the underlying entity.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.force_destroy(
	thing_identification,
	dont_destroy_entity
)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	thing:destroy(false, dont_destroy_entity)
	return nil
end

---Void a Thing, destroying its underlying entity but preserving its data and
---relationships for possible future reuse.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param skip_destroy boolean? If true, do not destroy the underlying entity. Use with caution.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.void(thing_identification, skip_destroy)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	if thing.state == "void" then return nil end
	thing:void(skip_destroy)
	return nil
end

---Devoid a Thing by attaching it to the given real or ghost entity. Thing must
---be in `void` state or the operation will fail.
---@param thing_id int64 The id of the Thing to devoid.
---@param entity LuaEntity A *valid* entity to attach to the Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.devoid(thing_id, entity)
	local thing = get_thing(thing_id)
	if not thing then return NOT_A_THING end
	if not entity or not entity.valid then
		return { code = "invalid_entity", message = "Invalid entity provided" }
	end
	if not thing:devoid(entity) then
		return { code = "devoid_failed", message = "Failed to devoid Thing" }
	end
	return nil
end

---Create a new Thing by invoking Factorio's `surface.create_entity` API.
---@param surface LuaSurface The surface to create the entity on.
---@param create_entity_params LuaSurface.create_entity_param The parameters to pass to `surface.create_entity`.
---@param create_thing_params things.CreateThingParams Parameters controlling how the Thing is created.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingSummary? thing Summary of the created Thing, or `nil` if there was an error.
function remote_interface.create_thing(
	surface,
	create_entity_params,
	create_thing_params
)
	-- Deduce final entity prototype name
	local name = create_entity_params.name
	if type(name) ~= "string" then name = name.name end
	if type(name) ~= "string" then
		return {
			code = "invalid_entity_name",
			message = "The entity name in create_entity_params is invalid.",
		}
	end
	if name == "entity-ghost" then name = create_entity_params.inner_name end

	-- Deduce Thing registration name
	local registration_name = name
	if create_thing_params.registration_name then
		registration_name = create_thing_params.registration_name
	end
	local registration = get_thing_registration(registration_name)
	if not registration then
		return {
			code = "unknown_registration",
			message = "No Thing registration with name '" .. tostring(
				registration_name
			) .. "' exists.",
		}
	end

	local devoid_thing = nil
	if create_thing_params.devoid then
		local dt, valid = resolve_identification(create_thing_params.devoid)
		if not valid then
			return {
				code = "cant_be_a_thing",
				message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier for the `devoid` parameter.",
			}
		end
		if not dt then
			return {
				code = "not_a_thing",
				message = "The specified Thing to devoid does not exist.",
			}
		end
		if dt.state ~= "void" then
			return {
				code = "not_void",
				message = "The specified Thing to devoid is not in `void` state.",
			}
		end
		devoid_thing = dt
	end

	local parent_thing = nil
	local add_child = false
	if devoid_thing then parent_thing = devoid_thing.parent end
	if create_thing_params.parent then
		if create_thing_params.devoid then
			return {
				code = "no_parent_and_devoid",
				message = "You may not specify both `parent` and `devoid` when creating a Thing.",
			}
		end
		local pt, valid = resolve_identification(create_thing_params.parent)
		if not valid then
			return {
				code = "cant_be_a_thing",
				message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier for the `parent` parameter.",
			}
		end
		if not pt then
			return {
				code = "not_a_thing",
				message = "The specified parent Thing does not exist.",
			}
		end
		parent_thing = pt
		add_child = true
	end
	local parent_orientation = nil
	local parent_entity = nil
	if parent_thing then
		parent_orientation = parent_thing:get_orientation(true)
		parent_entity = parent_thing:get_entity(true)
	end

	local pos = create_entity_params.position
	if parent_thing and create_thing_params.offset then
		if not parent_orientation then
			return {
				code = "parent_no_orientation",
				message = "The specified parent Thing has no orientation, so the `offset` parameter cannot be used.",
			}
		end
		if not parent_entity then
			return {
				code = "parent_no_entity",
				message = "The specified parent Thing has no entity, so the `offset` parameter cannot be used.",
			}
		end
		local ofs =
			parent_orientation:local_to_world_offset(create_thing_params.offset)
		local x, y = pos_lib.pos_get(parent_entity.position)
		local dx, dy = pos_lib.pos_get(ofs)
		pos = { x + dx, y + dy }
	end
	create_entity_params.position = pos

	create_entity_params.raise_built = false
	local entity = surface.create_entity(create_entity_params)
end

remote.add_interface("things", remote_interface)
