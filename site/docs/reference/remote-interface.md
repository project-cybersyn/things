---
sidebar_position: 3
---

# Remote Interface

Things exposes its API as a remote interface under the name `things`. All API functions have a standard call and return signature:

```lua
local err, ...results = remote.call("things", "api_method_name", ...args)
```

The following methods are available:

## get
```lua
---Gets basic information about a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingSummary? summary Summary of the Thing, or `nil` if the Thing doesn't exist.
function remote_interface.get(thing_identification) end
```

## create_thing
```lua
---Create a Thing from an entity.
---@param create_thing_params things.CreateThingParams Parameters controlling how the Thing is created.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingSummary? thing Summary of the created Thing, or `nil` if there was an error.
function remote_interface.create_thing(create_thing_params) end
```

## force_destroy
```lua
---Forcefully destroy a Thing and its underlying entity, if any.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param dont_destroy_entity boolean? If true, destroy the Thing but do not destroy the underlying entity.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.force_destroy(
	thing_identification,
	dont_destroy_entity
) end
```

## void
```lua
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
end
```

## silent_revive
```lua
---Silently revive a ghosted Thing. Returns the same values as `LuaEntity.silent_revive`.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return ItemWithQualityCounts?
---@return LuaEntity?
---@return LuaEntity?
function remote_interface.silent_revive(thing_identification) end
```

## set_tags
```lua
---Sets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param tags Tags The new tags to set on the Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_tags(thing_identification, tags) end
```

## get_transient_data
```lua
---Get transient data associated with a Thing. This data is not preserved when
---a Thing is blueprinted or copied.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return Tags|nil transient_data The transient data associated with this Thing, if any.
function remote_interface.get_transient_data(thing_identification) end
```

## set_transient_data
```lua
---Attach transient data to a Thing. This data is not preserved when
---a Thing is blueprinted or copied.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param key string The key to set in the transient data.
---@param value AnyBasic? The value to set in the transient data.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_transient_data(thing_identification, key, value) end
```

## add_child
```lua
---Adds a child Thing to a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@param child_key string|int|nil The key to assign the child in the parent Thing. If `nil`, uses the smallest free numeric key as determined by the Lua `#` operator.
---@param child_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The child Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.add_child(
	parent_identification,
	child_key,
	child_identification
) end
```

## remove_parent
```lua
---Removes a child Thing from its current parent.
---@param child_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The child Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.remove_parent(child_identification) end
```

## get_children
```lua
---Gets all children of a parent Thing.
---@param parent_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it. The parent Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.ThingChildrenSummary|nil children Map of child keys to child Thing summaries. `nil` if there was an error or the Thing doesn't have children.
function remote_interface.get_children(parent_identification) end
```

## modify_edge
```lua
---Modify a graph edge between two Things.
---@param graph_name string The name of the graph to create the edge in.
---@param operation "create"|"delete"|"toggle"|"set-data" The operation to perform on the edge.
---@param from things.ThingIdentification One side of the edge.
---@param to things.ThingIdentification The other side of the edge.
---@param data Tags? Additional data to set on the edge.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean? toggle_result If `operation` is "toggle", this will be `true` if the edge was created, or `false` if it was deleted. `nil` otherwise.
function remote_interface.modify_edge(graph_name, operation, from, to, data)
end
```

## get_edges
```lua
---Get all graph edges emanating from a Thing in a given graph. For undirected
---graphs, both `out_edges` and `in_edges` are relevant and must be checked.
---@param graph_name string The name of the graph to get edges from.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return {[int]: things.GraphEdge}|nil out_edges
---@return {[int]: things.GraphEdge}|nil in_edges
function remote_interface.get_edges(graph_name, thing_identification)
end
```

## get_edge
```lua
---If a graph edge exists between two Things, get it. In undirected graphs,
---the direction of the edge does not matter.
---@param graph_name string The name of the graph to get the edge from.
---@param from things.ThingIdentification One side of the edge.
---@param to things.ThingIdentification The other side of the edge.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return things.GraphEdge? edge The edge between the two Things, or `nil` if none exists.
function remote_interface.get_edge(graph_name, from, to)
end
```
