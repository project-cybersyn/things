# Types

## things.Id
```lua
---Unique identifier for a Thing.
---@alias things.Id int64
```

## things.ThingIdentification
```lua
---Thing identifier consumed by the Things API.
---Either the id of a Thing, or the LuaEntity currently representing it.
---@alias things.ThingIdentification things.Id|LuaEntity
```

## things.Status
```lua
---General statuses of a Thing.
---`void` means the Thing has no entity. Different from `destroyed` in that it will not be garbage collected and may later be re-attached to an entity.
---`real` means the Thing has a valid real entity.
---`ghost` means the Thing has a valid ghost entity.
---`destroyed` means the Thing is irrevocably gone. Destroyed things will be garbage-collected and cannot be used for any purpose.
---@alias things.Status "void"|"real"|"ghost"|"destroyed"
```

## things.ThingRegistration
```lua
---Registration options for a type of Thing.
---@class (exact) things.ThingRegistration
---@field public name string Name of the registered Thing type. This MUST be the same name as the key used to registere it, and SHOULD match the type of the corresponding entity.
---@field public intercept_construction? boolean If true, Things will intercept player-driven construction of entities of this type and create Things for them automatically. (default: false)
---@field public virtualize_orientation? Core.OrientationClass If given, the orientation of the Thing will be stored and managed by Things instead of relying on Factorio's built-in entity orientation. This allows for more complex orientation scenarios involving compound entities. The orientation will be promoted to the given orientation class if possible.
---@field public migrate_tags_callback? Core.RemoteCallbackSpec A remote callback to invoke when a Thing is built with unrecognized tags. This allows mods using non-Thing custom blueprint data to migrate to Things. The callback will be invoked as `callback(parsed_tags: Tags, raw_tags: Tags) -> Tags`, and should return the ultimate set of tags to assign to the Thing.
---@field public custom_events? {[things.EventName]: string} Mapping of Things event names to `CustomEventPrototype` names to raise for this Thing type. If not provided, no custom events will be raised for this Thing type.
---@field public no_garbage_collection? boolean If `true`, Things of this type will not be automatically garbage collected when Things thinks they are unreachable. You must manually destroy these Things when they are no longer needed. (default: false)
---@field public no_destroy_children_on_destroy? boolean If `true`, when a Thing of this type is destroyed, its children will NOT be automatically destroyed. (default: false)
---@field public no_void_children_on_void? boolean If `true`, when a Thing of this type is voided, its children will NOT be automatically voided. (default: false)
---@field public children? {[string|int]: things.ThingRegistration.Child} Specifications for automatic child creation.
```

## things.ThingRegistration.Child
```lua
---@class (exact) things.ThingRegistration.Child
---@field public create? LuaSurface.create_entity_param
---@field public offset? MapPosition Position offset of the child relative to the parent Thing's position
---@field public orientation? Core.Dihedral Orientation of the child relative to the parent Thing's orientation
```

## things.GraphRegistration
```lua
---Registration options for a graph of Things.
---@class (exact) things.GraphRegistration
---@field public name string Name of the registered graph.
---@field public directed? boolean Whether the graph is directed (default: false).
---@field public custom_events? {[things.GraphEventName]: string} Mapping of Things graph event names to `CustomEventPrototype` names to raise for this graph. If not provided, no custom events will be raised for this graph.
```

## things.GraphEdge
```lua
---Representation of an edge in a graph of Things.
---@class (exact) things.GraphEdge
---@field public from int Edge emanates from this Thing ID. (In undirected graphs, the lower id.)
---@field public to int Edge points to this Thing ID. (In undirected graphs, the higher id.)
---@field public data? Tags Optional user data associated with this edge.
```

## things.ParentRelationshipInfo
```lua
---Info about a Thing's relationship to its parent.
---[1]: The ID of the parent Thing.
---[2]: The key under which this Thing is registered in its parent's children.
---[3]: The position of this Thing relative to its parent, if any.
---[4]: The orientation of this Thing relative to its parent, if any.
---@alias things.ParentRelationshipInfo [int64, string|int, MapPosition?, Core.Dihedral?]
```
