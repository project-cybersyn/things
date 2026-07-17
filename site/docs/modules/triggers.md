---
sidebar_position: 7
---

# Triggers

![Stability - Experimental](https://shields.io/badge/stability-experimental-orange?style=for-the-badge)

The triggers module allows Things to receive scripted events related to circuit network conditions without the use of polling.

## Client Methods

### triggers_v1.create_trigger
Create a trigger object attached to a parent Thing. When the object is triggered, the custom event `on_trigger` will fire for the parent Thing.

```lua
---@param parent_thing_id things.Id The thing id of the parent thing to attach the trigger to.
---@param child_index string? The key to use for the trigger child entity. If `nil`, the default key "_trigger" will be used.
---@param debounce_ticks? uint? The number of ticks to wait before allowing the trigger to fire again. If `nil`, the trigger can fire every tick.
---@param control_behavior? LandMineBlueprintControlBehavior The control behavior to use for the trigger mine. If not given, a default control behavior will be used that triggers on the "things-signal-trigger" hidden virtual signal.
---@return things.Id? trigger_id The unique identifier for the created trigger. Returns `nil` if the parent Thing does not exist or the trigger could not be created.
---@return LuaEntity? trigger_entity The entity controlling the trigger. Returns `nil` if the parent Thing does not exist or the trigger could not be created.
local trigger_id, trigger_entity = things_client.triggers_v1.create_trigger(
	parent_thing_id,
	child_index,
	debounce_ticks,
	control_behavior
)
```

### triggers_v1.arm_trigger
Arm or disarm a previously created trigger object. (Note that due to integer size limitations, disarming a trigger will set its timeout to approximately 974 days, after which time it will rearm. True permanent disarming requires calling this method again before then or destroying the trigger.)

```lua
---@param trigger_id things.Id The unique identifier for the trigger to arm or disarm. This is the value returned by `create_trigger`.
---@param is_armed boolean Whether to arm (`true`) or disarm (`false`) the trigger.
---@return boolean success Returns `true` if the trigger was successfully armed or disarmed, or `false` if the trigger does not exist or could not be modified.
local success = things_client.triggers_v1.arm_trigger(trigger_id, is_armed)
```

### triggers_v1.create_circuit_change_detector
Create a specialized trigger designed to detect changes in circuit inputs. You must provide a red and/or green wire connector to be monitored for changes. The parent Thing will receive trigger events whenever the monitored circuit inputs change.

```lua
---@param parent_thing_id things.Id The thing id of the parent thing to attach the circuit change detector to.
---@param prefix string A prefix to use for the names of the invisible combinators created.
---@param red_circuit LuaWireConnector? The red wire connector to monitor for changes. If `nil`, no red wire monitoring will be performed.
---@param green_circuit LuaWireConnector? The green wire connector to monitor for changes. If `nil`, no green wire monitoring will be performed.
---@return things.Id? trigger_id The unique identifier for the created trigger. Returns `nil` if the trigger could not be created.
local trigger_id = things_client.triggers_v1.create_circuit_change_detector(
	parent_thing_id,
	prefix,
	red_circuit,
	green_circuit
)
```

### triggers_v1.destroy_circuit_change_detector
Destroy a previously created circuit change detector. Note that it is rarely necessary to call this function, as destroying the parent Thing will automatically destroy all of its children, including the circuit change detector.

```lua
---@param parent_thing_id things.Id The thing id of the parent thing to detach the circuit change detector from.
---@param prefix string The prefix used with `create_circuit_change_detector` when the circuit change detector was created.
things_client.triggers_v1.destroy_circuit_change_detector(parent_thing_id, prefix)
```

## Custom Events

### on_trigger
This event is raised when a trigger is activated.

The type of this event's parameter is `things.EventData.on_trigger`:

```lua
---@class (exact) things.EventData.on_trigger
---@field public thing_id things.Id The ID of the Thing that owns the trigger device.
---@field public trigger_id things.Id The ID of the trigger device that was activated.
---@field public trigger_data Any? Additional data associated with the trigger. This will be absent if no additional data was provided when the trigger was created.
```
