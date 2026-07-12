---
sidebar_position: 4
---

# Parent-Child

![Stability - Beta](https://shields.io/badge/stability-beta-yellow?style=for-the-badge)

The parent-child module allows a parent Thing to have one or more Things or entities as children. These children will have their lifecycle, position, and orientation managed relative to that of the parent Thing.

Parent-child relationships can be created automatically for registered Things by specifying a set of children that will be automatically created alongside the parent Thing. It is also possible to add and remove children dynamically at runtime.

## Registration

## Client Methods

## Custom Events

### on_children_normalized
Raised for a parent Thing after all its registered children have been created, devoided, revived, or destroyed in order to match their lifecycle state appropriately with the parent.

This event is only raised for children registered in the data phase, and is NOT raised for any children dynamically added or removed during runtime.

The type of this event's parameter is `things.EventData.on_children_normalized`:

```lua
---@class (exact) things.EventData.on_children_normalized
---@field public thing things.ThingShortSummary Summary of the Thing whose children were normalized.
---@field public entity LuaEntity? The current entity of the Thing, equivalent to `thing.entity`.
```
