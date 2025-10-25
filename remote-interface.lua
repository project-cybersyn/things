-- Things API.

require("types")

local pos_lib = require("lib.core.math.pos")
local thing_lib = require("control.thing")
local reg_lib = require("control.registration")
local graph_lib = require("control.graph")

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
	thing:set_tags(tags, true)
	return nil
end

---Modify a graph edge between two Things.
---@param graph_name string The name of the graph to create the edge in.
---@param operation "create"|"delete"|"toggle"|"set-data" The operation to perform on the edge.
---@param from things.ThingIdentification One side of the edge.
---@param to things.ThingIdentification The other side of the edge.
---@param data Tags? Additional data to set on the edge.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean? toggle_result If `operation` is "toggle", this will be `true` if the edge was created, or `false` if it was deleted. `nil` otherwise.
function remote_interface.modify_edge(graph_name, operation, from, to, data)
	local from_thing, valid_id1 = resolve_identification(from)
	local to_thing, valid_id2 = resolve_identification(to)
	if not valid_id1 or not valid_id2 then return CANT_BE_A_THING end
	if not from_thing or not to_thing then return NOT_A_THING end
	local graph = graph_lib.get_graph(graph_name)
	if not graph then
		return {
			code = "invalid_graph",
			message = "No graph with name '" .. tostring(graph_name) .. "' exists.",
		}
	end
	local edge = graph:get_edge(from_thing.id, to_thing.id)
	if operation == "create" then
		if edge then
			return { code = "edge_exists", message = "Edge already exists." }
		end
		graph_lib.connect(graph, from_thing, to_thing, data)
	elseif operation == "delete" then
		if not edge then
			return { code = "edge_does_not_exist", message = "Edge does not exist." }
		end
		graph_lib.disconnect(graph, from_thing, to_thing)
	elseif operation == "toggle" then
		if edge then
			graph_lib.disconnect(graph, from_thing, to_thing)
			return nil, false
		else
			graph_lib.connect(graph, from_thing, to_thing, data)
			return nil, true
		end
	elseif operation == "set-data" then
		if not edge then
			return { code = "edge_does_not_exist", message = "Edge does not exist." }
		end
		graph_lib.set_edge_data(graph, from_thing, to_thing, data)
	end
	return nil
end

---Get all graph edges emanating from a Thing in a given graph. For undirected
---graphs, both `out_edges` and `in_edges` are relevant and must be checked.
---@param graph_name string The name of the graph to get edges from.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[int]: things.GraphEdge}|nil out_edges
---@return {[int]: things.GraphEdge}|nil in_edges
function remote_interface.get_edges(graph_name, thing_identification)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local graph = graph_lib.get_graph(graph_name)
	if not graph then
		return {
			code = "invalid_graph",
			message = "No graph with name '" .. tostring(graph_name) .. "' exists.",
		}
	end
	local out_edges, in_edges = graph:get_edges(thing.id)
	return nil, out_edges, in_edges
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

---Removes a child Thing from its current parent.
---@param child_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The child Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.remove_parent(child_identification)
	local child, valid_child = resolve_identification(child_identification)
	if valid_child then return CANT_BE_A_THING end
	if not child then return NOT_A_THING end
	local removed = child:remove_parent()
	if not removed then
		return {
			code = "could_not_remove_child",
			message = "Could not remove child; the specified Thing is not a child of any parent.",
		}
	end
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

---Silently revive a ghosted Thing. Returns the same values as `LuaEntity.silent_revive`.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return ItemWithQualityCounts?
---@return LuaEntity?
---@return LuaEntity?
function remote_interface.silent_revive(thing_identification)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	if thing.state ~= "ghost" then
		return {
			code = "not_ghost",
			message = "The specified Thing is not in `ghost` state.",
		}
	end
	local r1, r2, r3 = thing:revive()
	if not r1 then
		return {
			code = "revive_failed",
			message = "Failed to silently revive the specified Thing.",
		}
	end
	return nil, r1, r2, r3
end

---Forcefully destroy a Thing and its underlying entity, if any.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param dont_destroy_entity boolean? If true, destroy the Thing but do not destroy the underlying entity.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.force_destroy(
	thing_identification,
	dont_destroy_entity
)
	-- TODO: fix this.
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
---@param skip_destroy_children boolean? If true, do not recursively destroy child Thing entities when voiding them. Use with caution.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.void(
	thing_identification,
	skip_destroy,
	skip_destroy_children
)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	if thing.state == "void" then return nil end
	thing:void(skip_destroy, skip_destroy_children)
	return nil
end

---Get adjusted position and orientation of a Thing relative to a parent.
---Can be useful when creating child entities.
---@param thing_identification things.ThingIdentification The parent Thing to adjust against.
---@param offset MapPosition? The position of the child relative to the parent.
---@param transform Core.Dihedral? The transform of the child relative to the parent.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return MapPosition? adjusted_position The adjusted position of the child.
---@return Core.Orientation? adjusted_orientation The adjusted orientation of the child.
function remote_interface.get_adjusted_pos_and_orientation(
	thing_identification,
	offset,
	transform
)
	local parent_thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not parent_thing then return NOT_A_THING end
	return nil,
		thing_lib.get_adjusted_pos_and_orientation(parent_thing, offset, transform)
end

---Create a Thing from an entity.
---@param create_thing_params things.CreateThingParams Parameters controlling how the Thing is created.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingSummary? thing Summary of the created Thing, or `nil` if there was an error.
function remote_interface.create_thing(create_thing_params)
	local entity = create_thing_params.entity
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
		if not dt:devoid(entity) then
			return {
				code = "devoid_failed",
				message = "Failed to devoid the specified Thing.",
			}
		end
		return nil, dt:summarize()
	end

	local name = create_thing_params.name
	local is_ghost = entity.type == "entity-ghost"
	if not name then name = is_ghost and entity.ghost_name or entity.name end
	local registration = reg_lib.get_thing_registration(name)
	if not registration then
		return {
			code = "invalid_name",
			message = "No Thing registration with name '"
				.. tostring(name)
				.. "' exists.",
		}
	end

	local parent_thing = nil
	if create_thing_params.parent then
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
	end

	local thing, was_created, err = thing_lib.make_thing(entity, name)
	if not was_created or not thing then
		return {
			code = "creation_failed",
			message = "Failed to create Thing",
		}
	end

	local child_was_added = false
	if parent_thing then
		child_was_added = parent_thing:add_child(
			create_thing_params.child_index,
			thing,
			create_thing_params.relative_pos,
			create_thing_params.relative_orientation,
			true
		)
	end

	-- Broadcast child initialization
	thing:initialize()
	-- Broadcast parent child-change
	if child_was_added and parent_thing then
		parent_thing:raise_event(
			"things.thing_children_changed",
			parent_thing,
			thing,
			nil
		)
	end

	return nil, thing:summarize()
end

remote.add_interface("things", remote_interface)
