-- Things API.

require("types")

local pos_lib = require("lib.core.math.pos")
local thing_lib = require("control.thing")
local reg_lib = require("control.registration")
local graph_lib = require("control.graph")
local tlib = require("lib.core.table")
local extraction_lib = require("control.blueprint-extraction")
local bpop_lib = require("control.op.blueprint")
local constants = require("control.constants")

local get_thing_by_unit_number = thing_lib.get_by_unit_number
local get_thing = thing_lib.get_by_id
local type = _G.type

local EMPTY = tlib.EMPTY
local NAME_TAG = constants.NAME_TAG
local PARENT_TAG = constants.PARENT_TAG
local TAGS_TAG = constants.TAGS_TAG

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

--------------------------------------------------------------------------------
-- INFO AND LIFECYCLE
--------------------------------------------------------------------------------

---Given an entity, gets the associated Thing ID.
---@param entity LuaEntity The entity to look up.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return int64? thing_id The ID of the Thing associated with the entity, or `nil` if none exists.
function remote_interface.get_thing_id(entity)
	if not entity or not entity.valid then
		return {
			code = "invalid_entity",
			message = "The specified entity is nil or invalid.",
		}
	end
	local thing = get_thing_by_unit_number(entity.unit_number)
	if not thing then return nil, nil end
	return nil, thing.id
end

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

	if create_thing_params.tags then
		thing:set_tags(create_thing_params.tags, true, true, "api")
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

---Silently revive a ghosted Thing. Returns the same values as `LuaEntity.silent_revive`.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return ItemWithQualityCount[]?
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

---When a blueprint is extracted by user code calling `create_blueprint`,
---no event is raised that Things can intercept. Therefore, this method must
---be called to tag the Things in the blueprint with the appropriate data.
---@param bp Core.Blueprintish The LuaItemStack or LuaRecord on which `create_blueprint` was called.
---@param bp_to_world {[integer]: LuaEntity} The mapping from blueprint entity indices to world entities returned by `create_blueprint`.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.script_create_blueprint(bp, bp_to_world)
	-- TODO: better valid checks/error handling here
	extraction_lib.extract_blueprint(bp, bp_to_world)
	return nil
end

---When a blueprint is built by user code calling `build_blueprint`, no
---prebuild event is given by Factorio. Therefore, this method must be called
---BEFORE calling `build_blueprint` to allow Things to properly restore state.
---Note that when calling `build_blueprint` you must also enable `raise_built`.
---@param bp Core.Blueprintish The LuaItemStack or LuaRecord on which `create_blueprint` will be called.
---@param player LuaPlayer? The player for whom the blueprint is being built. Can be nil if the blueprint is being built by script.
---@param surface LuaSurface
---@param orientation_data Core.BlueprintOrientationData
---@param build_mode defines.build_mode
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean was_prebuilt True if the blueprint was prebuilt (i.e. a prebuild op was generated and applied), false if it was not (e.g. because there were no Things in the blueprint).
function remote_interface.script_prebuild_blueprint(
	bp,
	player,
	surface,
	orientation_data,
	build_mode
)
	local was_prebuilt = bpop_lib.maybe_generate_blueprint_op(
		bp,
		player,
		surface,
		orientation_data,
		build_mode
	)
	return nil, was_prebuilt
end

--------------------------------------------------------------------------------
-- POS AND ORIENTATION
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- TAGS
--------------------------------------------------------------------------------

---Sets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param tags Tags The new tags to set on the Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_tags(thing_identification, tags)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	thing:set_tags(tags, true, nil, "api")
	return nil
end

---Set a single tag on a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param key string The tag key to set.
---@param value AnyBasic|nil The tag value to set. `nil` removes the tag.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_tag(thing_identification, key, value)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local new_tags = tlib.assign({}, thing.tags)
	new_tags[key] = value
	---@diagnostic disable-next-line: cast-local-type
	if not next(new_tags) then new_tags = nil end
	thing:set_tags(new_tags, true, nil, "api")
	return nil
end

---Remove a single tag from a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param key string The tag key to remove.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.remove_tag(thing_identification, key)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local new_tags = thing.tags
	if not new_tags or not new_tags[key] then return nil end
	new_tags[key] = nil
	---@diagnostic disable-next-line: cast-local-type
	if not next(new_tags) then new_tags = nil end
	thing:set_tags(new_tags, true, nil, "api")
	return nil
end

---Shallow merges new tags into the existing tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param tags Tags The tags to merge into the Thing's existing tags.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.merge_tags(thing_identification, tags)
	local thing, valid_id = resolve_identification(thing_identification)
	if not valid_id then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local new_tags = thing.tags or {}
	tlib.assign(new_tags, tags)
	thing:set_tags(new_tags, true, nil, "api")
	return nil
end

---Get transient data associated with a Thing. This data is not preserved when
---a Thing is blueprinted or copied.
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
---a Thing is blueprinted or copied.
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

--------------------------------------------------------------------------------
-- PARENT/CHILD
--------------------------------------------------------------------------------

---Adds a child Thing to a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_key string The key to assign the child in the parent Thing.
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
	if type(child_key) ~= "string" then
		return {
			code = "invalid_child_key",
			message = "The child key must be a string.",
		}
	end
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

---Get the number of children of a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return uint? count The number of children of the parent Thing, or `nil` if there was an error or the Thing doesn't exist.
function remote_interface.get_num_children(parent_identification)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	return nil, parent.children and table_size(parent.children) or 0
end

---Adds a transient child entity to a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_index string|int The index to assign the transient child in the parent Thing.
---@param child_entity LuaEntity The child entity to add as a transient child.
---@param replace? boolean If `true`, will destroy and replace an existing child.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean? added True if the transient child was added, false if the index was already in use, nil on error.
function remote_interface.add_transient_child(
	parent_identification,
	child_index,
	child_entity,
	replace
)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	if not child_entity or not child_entity.valid then
		return {
			code = "invalid_entity",
			message = "The specified child entity is nil or invalid.",
		}
	end
	return nil, parent:add_transient_child(child_index, child_entity, replace)
end

---Remove a transient child entity from a parent Thing, optionally destroying it.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_index string|int The index of the transient child to remove.
---@param destroy_child boolean? If true, destroy the transient child entity after removing it. Defaults to false.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.remove_transient_child(
	parent_identification,
	child_index,
	destroy_child
)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	local removed = parent:remove_transient_child(child_index, destroy_child)
	if not removed then
		return {
			code = "no_such_transient_child",
			message = "Could not remove transient child; the specified index does not exist.",
		}
	end
end

---Get all transient children from a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[string|int]: LuaEntity}|nil children Map of child indices to transient child entities. `nil` if there was an error or the Thing doesn't exist. An empty object if the Thing has no transient children.
function remote_interface.get_transient_children(parent_identification)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	return nil, parent.transient_children or EMPTY
end

---Get one transient child by index from a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_index string|int The index of the transient child to get.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return LuaEntity|nil child The transient child Thing, or nil if it doesn't exist.
function remote_interface.get_transient_child(
	parent_identification,
	child_index
)
	local parent, valid_parent = resolve_identification(parent_identification)
	if not valid_parent then return CANT_BE_A_THING end
	if not parent then return NOT_A_THING end
	return nil, (parent.transient_children or EMPTY)[child_index]
end

--------------------------------------------------------------------------------
-- GRAPH
--------------------------------------------------------------------------------

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

---If a graph edge exists between two Things, get it. In undirected graphs,
---the direction of the edge does not matter.
---@param graph_name string The name of the graph to get the edge from.
---@param from things.ThingIdentification One side of the edge.
---@param to things.ThingIdentification The other side of the edge.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.GraphEdge? edge The edge between the two Things, or `nil` if none exists.
function remote_interface.get_edge(graph_name, from, to)
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
	return nil, edge
end

remote.add_interface("things", remote_interface)

--------------------------------------------------------------------------------
-- METADATA
--------------------------------------------------------------------------------

local metadata_v1 = {}

metadata_v1.get = remote_interface.get

metadata_v1.get_thing_id = remote_interface.get_thing_id

---Get the given Thing's status.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.Status? status The status of the Thing, or `nil` if there was an error or the Thing doesn't exist.
function metadata_v1.get_status(thing_identification)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	return nil, thing.state
end

---Given a set of Factorio blueprint tags attached to a Thing, retrieve the
---tags of the actual underlying Thing. You must call this method instead of
---decoding the change yourself to avoid being dependent on Things' undocumented
---internal data formats.
---@param blueprint_tags Tags The tags attached to a blueprint entity.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return string? thing_name The registration name of the Thing encoded by these tags. Will always be present if there is no error.
---@return Tags? thing_tags The tags assigned to underlying Thing, or `nil` if this has no tags.
---@return uint? parent_index If the Thing encoded by these tags has a parent Thing within the blueprint, the index of the parent entity in the blueprint. Will be `nil` if there is no parent.
function metadata_v1.decode_blueprint_tags(blueprint_tags)
	if not blueprint_tags then
		return {
			code = "invalid_argument",
			message = "The provided tags are nil.",
		}
	end
	local thing_name = blueprint_tags[NAME_TAG]
	if type(thing_name) ~= "string" then return NOT_A_THING end
	local thing_tags = blueprint_tags[TAGS_TAG] --[[@as Tags?]]
	local parent_index = nil
	local parent_info = blueprint_tags[PARENT_TAG]
	if parent_info then parent_index = parent_info[1] end
	return nil, thing_name, thing_tags, parent_index
end

remote.add_interface("things-metadata-v1", metadata_v1)

--------------------------------------------------------------------------------
-- TAGS
--------------------------------------------------------------------------------

local tags_v1 = {}

---Get the given tag of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param key string The tag key to retrieve.
function tags_v1.get_tag(thing_identification, key)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	local tags = thing.tags
	return nil, tags and tags[key]
end

tags_v1.set_tag = remote_interface.set_tag

---Get all tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return Tags? tags The tags of the Thing, or `nil` if there was an error or the Thing doesn't exist. Will be `nil` if the Thing has no tags.
function tags_v1.get_tags(thing_identification)
	local thing, valid = resolve_identification(thing_identification)
	if not valid then return CANT_BE_A_THING end
	if not thing then return NOT_A_THING end
	return nil, thing.tags
end

tags_v1.set_tags = remote_interface.set_tags

remote.add_interface("things-tags-v1", tags_v1)

--------------------------------------------------------------------------------
-- COOPERATIVE BLUEPRINT EDITING
--------------------------------------------------------------------------------

local cbe_v1 = {}

---@type things.Error
local NO_BLUEPRINT = {
	code = "no_blueprint",
	message = "No blueprint is currently being edited.",
}

---Get entities from the blueprint being edited.
---@param name string? If given, returns only entities with the given prototype name.
---@param name_prefix string? If given, returns only entities whose prototype name starts with the given prefix. Ignored if `name` is given.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ExtractedEntity[]? entities The entities currently extracted from the blueprint and being edited, or `nil` if there was an error.
function cbe_v1.get_entities(name, name_prefix)
	local ce = extraction_lib.current_extraction
	if not ce then return NO_BLUEPRINT end
	if name then
		local result = {}
		for _, entity in pairs(ce.by_index) do
			if entity.bp_entity.name == name then result[#result + 1] = entity end
		end
		return nil, result
	elseif name_prefix then
		local result = {}
		for _, entity in pairs(ce.by_index) do
			if entity.bp_entity.name:sub(1, #name_prefix) == name_prefix then
				result[#result + 1] = entity
			end
		end
		return nil, result
	else
		return nil, ce.by_index
	end
end

---@param index uint Index of entity to replace, corresponding to the indices of entities returned by `get_extracted_entities`.
---@param new_entity things.PartialBlueprintEntity The new entity to replace the old one with. Position and direction will automatically be copied if not given.
---@param keep_wires boolean? If true, when replacing an entity, will attempt to keep the same circuit connections on the new entity as were present on the old entity, if applicable. Defaults to false.
function cbe_v1.replace_entity(index, new_entity, keep_wires)
	local ce = extraction_lib.current_extraction
	if not ce then return NO_BLUEPRINT end
	ce:replace(index, new_entity, keep_wires)
end

remote.add_interface("things-blueprint-editing-v1", cbe_v1)
