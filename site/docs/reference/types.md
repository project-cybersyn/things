---
sidebar_position: 1
---

# Types

These are the core Lua data types used by the Things API.

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
---@field public name string Name of the registered Thing type. This MUST be the same name as the key used to register it, and SHOULD match the prototype name of the corresponding entity.
---@field public intercept_construction? boolean If true, Things will intercept player-driven construction of entities of this type and create Things for them automatically. (default: false)
---@field public virtualize_orientation? Core.OrientationClass If given, the orientation of the Thing will be stored and managed by Things instead of relying on Factorio's built-in entity orientation. This allows for more complex orientation scenarios involving compound entities. The orientation will be promoted to the given orientation class if possible.
---@field public migrate_tags_callback? Core.RemoteCallbackSpec A remote callback to invoke when a Thing is built with unrecognized tags. This allows mods using non-Thing custom blueprint data to migrate to Things. The callback will be invoked as `callback(unrecognized_tags: Tags) -> Tags`, and should return a set of Tags to be applied to the Thing.
---@field public initial_tags_callback? Core.RemoteCallbackSpec A remote callback to invoke when a Thing of this type is created through intercepting a construction event. This allows mods to set initial tags on Things of this type. The callback will be invoked as `callback(entity: LuaEntity) -> tags: Tags|nil`, and should return a set of Tags to be applied to the new Thing.
---@field public custom_events? {[things.EventName]: string} Mapping of Things event names to `CustomEventPrototype` names to raise for this Thing type. If not provided, no custom events will be raised for this Thing type.
---@field public no_garbage_collection? boolean If `true`, Things of this type will not be automatically garbage collected when Things thinks they are unreachable. You must manually destroy these Things when they are no longer needed. (default: false)
---@field public no_destroy_children_on_destroy? boolean If `true`, when a Thing of this type is destroyed, its children will NOT be automatically destroyed. (default: false)
---@field public no_void_children_on_void? boolean If `true`, when a Thing of this type is voided, its children will NOT be automatically voided. (default: false)
---@field public children? {[string|int]: things.ThingRegistration.Child} Specifications for automatic child creation.
---@field public allow_in_cursor? "never" Controls the behavior of entity-pipette and cursor stack for this Thing. If set to "never", Things of this type cannot be picked up into the player's cursor. (default: nil, meaning Things of this type use normal Factorio behavior.)
```

## things.ThingRegistration.Child
```lua
---@class (exact) things.ThingRegistration.Child
---@field public create? LuaSurface.create_entity_param
---@field public offset? MapPosition Position offset of the child relative to the parent Thing's position
---@field public orientation? Core.Dihedral Orientation of the child relative to the parent Thing's orientation
---@field public lifecycle_type? "real-real"|"void-real"|"ghost-real" Determines lifecycle of child based on parent. `real-real` means child is real regardless of whether parent is ghost or real. `void-real` means child is real if parent is real, void if parent is ghost. `ghost-real` means child is real if parent is real, ghost if parent is ghost. (default: `ghost-real`)
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

## things.ThingChildrenSummary
```lua
---A summary of a Thing's children, indexed by child key.
---@alias things.ThingChildrenSummary {[string|int]: things.ThingSummary}
```

## things.ThingSummary
```lua
---Serializable summary information about a Thing.
---@class (exact) things.ThingSummary
---@field public id things.Id The id of the Thing.
---@field public name string The name of the Thing's registration.
---@field public entity LuaEntity? The current entity of the Thing, if it has one. This entity is pre-checked for validity at the time the summary is generated.
---@field public status things.Status The current status of the Thing.
---@field public virtual_orientation Core.Orientation? The current virtual orientation of the Thing, if it has one. This will always be nil for Thing types that do not virtualize orientation.
---@field public tags Tags? The current tags of the Thing.
---@field public parent? things.ParentRelationshipInfo Information about this Thing's parent, if any.
---@field public transient_children? {[int|string]: LuaEntity} Map from child indices (which may be numbers or strings) to child entities that are not themselves Things.
```

## things.CreateThingParams
```lua
---Options controlling how a Thing is created via `create_thing`.
---@class (exact) things.CreateThingParams
---@field public entity LuaEntity The *valid* entity to associate the new Thing with. This entity must not already be associated with an existing Thing.
---@field public name? string If given, the new Thing will be created as an instance of the registered Thing type with this name. If not given, name will be inferred from the entity type.
---@field public parent? things.ThingIdentification If given, create the new Thing as a child of this Thing.
---@field public child_index? int|string The index of the new Thing within its parent's children, if any. If not given, the new Thing will be added at the end of the parent's children.
---@field public relative_pos? MapPosition The position of the new Thing relative to its parent, if any.
---@field public relative_orientation? Core.Dihedral The orientation of the new Thing relative to its parent, if any.
---@field public devoid? things.ThingIdentification If given, instead of creating a new Thing, devoid the given voided Thing. Cannot be given with `parent`; the new Thing will retain the parent of the voided Thing.
```

## things.ExtractedEntity
```lua
---Entity within a blueprint being extracted.
---@class (exact) things.ExtractedEntity
---@field public index int The index of the entity within the extraction process.
---@field public bp_entity BlueprintEntity The blueprint entity data.
---@field public entity LuaEntity The in-world entity this blueprint entity represents.
---@field public thing_id things.Id? The Thing this blueprint entity represents.
---@field public deleted true? If `true`, this entity was deleted by an atomic blueprint operation.
```
