---
sidebar_position: 2
---

# Events

These are the events that can be bound using `custom_events`.

## on_initialized
```lua
---Event fired when a Thing with a new ID is generated in the world.
---Does not apply to undo, revival, etc of pre-existing Things.
---@alias things.EventData.on_initialized things.ThingSummary
```

## on_status
```lua
---Event fired when a Thing's lifecycle status changes.
---@class (exact) things.EventData.on_status
---@field public thing things.ThingSummary Summary of the Thing whose status changed.
---@field public old_status things.Status The previous status of the Thing.
---@field public new_status things.Status The new status of the Thing.
```

## on_tags_changed
```lua
---Event parameters for when Thing tags change. Note that for performance
---reasons, Things does not deep compare tags, so this event may be raised
---in certain cases even when tags haven't meaningfully changed.
---@class (exact) things.EventData.on_tags_changed
---@field public thing things.ThingSummary Summary of the Thing whose tags changed.
---@field public new_tags Tags The new tags of the Thing.
---@field public old_tags Tags The previous tags of the Thing.
---@field public cause "api"|"engine" Source of the tag change event.
```

## on_orientation_changed
```lua
---Event raised when the orientation of a Thing changes.
---@class (exact) things.EventData.on_orientation_changed
---@field public thing things.ThingSummary Summary of the Thing whose orientation changed.
---@field public old_orientation? Core.Orientation The previous orientation of the Thing.
---@field public new_orientation Core.Orientation The new orientation of the Thing.
```

## on_position_changed
```lua
---Event raised when a Thing's position changes.
---@class (exact) things.EventData.on_position_changed
---@field public thing things.ThingSummary Summary of the Thing whose position changed.
---@field public old_position? MapPosition The previous position of the Thing.
---@field public new_position MapPosition The new position of the Thing.
```

## on_children_changed
```lua
---Event raised when the composition of a Thing's children changes.
---@class (exact) things.EventData.on_children_changed
---@field public thing things.ThingSummary Summary of the Thing whose children changed.
---@field public added things.ThingSummary|nil If a child was added, its summary.
---@field public removed things.ThingSummary[]|nil Summary of the removed children.
```

## on_parent_changed
```lua
---Event raised when a Thing's parent changes.
---@class (exact)things.EventData.on_parent_changed
---@field public thing things.ThingSummary Summary of the Thing whose parent changed.
---@field public new_parent things.ThingSummary|nil Summary of the new parent, if any.
```

## on_child_status
```lua
---Event raised when a Thing's child changes status.
---@class (exact) things.EventData.on_child_status
---@field public thing things.ThingSummary Summary of the Thing whose children's status changed.
---@field public child things.ThingSummary Summary of the child whose status changed.
---@field public child_index string|int The key under which the child is registered in the parent.
---@field public old_child_status things.Status The previous status of the child.
```

## on_parent_status
```lua
---Event raised when a Thing's parent changes status.
---@class (exact) things.EventData.on_parent_status
---@field public thing things.ThingSummary Summary of the Thing whose parent's status changed.
---@field public parent things.ThingSummary Summary of the parent whose status changed.
---@field public old_parent_status things.Status The previous status of the parent.
```

## on_edge_changed
This is a graph event.
```lua
---Notifies a graph when its edge set changes.
---@class (exact) things.EventData.on_edge_changed
---@field public change "create"|"delete"|"set-data" The type of change that occurred.
---@field public graph_name string The name of the graph whose edges changed.
---@field public edge things.GraphEdge Edge that was changed.
---@field public from things.ThingSummary Summary of the Thing at the from end of the edge.
---@field public to things.ThingSummary Summary of the Thing at the to end of the edge
```

## on_edge_status
```lua
---Notifies a Thing when another thing connected it by a graph edge changes status.
---@class (exact) things.EventData.on_edge_status
---@field public thing things.ThingSummary Thing opposite the changed thing along the given edge.
---@field public changed_thing things.ThingSummary Thing whose status changed.
---@field public graph_name string The name of the graph where the status changed.
---@field public edge things.GraphEdge Edge whose status changed.
---@field public old_status things.Status The previous status of the opposite Thing.
---@field public new_status things.Status The new status of the opposite Thing.
```

## on_children_normalized
```lua
---Event that takes place after automatically generated children are normalized.
---This means that all automatic children have been created, devoided, or revived
---as necessary to match the current state of the parent Thing.
---@alias things.EventData.on_children_normalized things.ThingSummary
```

## on_immediate_voided
```lua
---Event raised inline when a Thing is voided. This event occurs mid-frame and
---you should take care to avoid causing event cancer. The only valid use
---for this event is to collect data about the Thing before its entity is
---destroyed.
---@alias things.EventData.on_immediate_voided things.ThingSummary
```
