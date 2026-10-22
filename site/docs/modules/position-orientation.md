---
sidebar_position: 3
---

# Position and Orientation

![Stability - Beta](https://shields.io/badge/stability-beta-yellow?style=for-the-badge)

The position and orientation model deals with the position of Things and their orientation (direction and mirroring) in the world.

## Client Methods

### teleport

### set_orientation

Set the orientation of a Thing. This function will fail returning `false` if the thing doesn't exist, is already oriented in the given way, or cannot be oriented manually.

```lua
---@param thing things.Id Thing ID to orient.
---@param orientation Core.Orientation Orientation to set for the Thing.
---@return boolean oriented `true` if the orientation was successfully set, `false` otherwise.
local oriented = things_client.orientation_v1.set_orientation(thing, orientation)
```

## Custom Events

### on_position_changed

### on_orientation_changed
