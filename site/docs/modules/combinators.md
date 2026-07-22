---
sidebar_position: 6
---

# Combinators

![Stability - Experimental](https://shields.io/badge/stability-experimental-orange?style=for-the-badge)

The combinators module allows the registration and creation of standardized invisible variants of vanilla Factorio combinators, as well as mod-customized combinators.

This central repository of invisible combinator variants can be used by mods wishing to implement their functionality using hidden circuit networks.

## Registration

## Data Phase Methods

### combinators_v1.register
Register a combinator type in the shared combinator registry.

```lua
---@param registration things.CombinatorRegistration
combinators_v1.register(registration)
```

### combinators_v1.get_invisible_combinator_prototype
Get a generic invisible `CombinatorPrototype` template.

```lua
---@return data.CombinatorPrototype prototype
local prototype = combinators_v1.get_invisible_combinator_prototype()
```

### combinators_v1.get_invisible_constant_combinator_prototype
Get a generic invisible `ConstantCombinatorPrototype` template.

```lua
---@return data.ConstantCombinatorPrototype prototype
local prototype = combinators_v1.get_invisible_constant_combinator_prototype()
```

### combinators_v1.get_invisible_land_mine_prototype
Get a generic invisible `LandMinePrototype` template suitable for circuit-triggered mine logic.

```lua
---@return data.LandMinePrototype prototype
local prototype = combinators_v1.get_invisible_land_mine_prototype()
```

### combinators_v1.get_trigger_mine_prototype
Create an invisible trigger mine prototype that raises a custom event when triggered.

```lua
---@param custom_event_name string The custom event name to raise on trigger.
---@param effect_id string? The script effect id. Defaults to "trigger".
---@return data.LandMinePrototype prototype
local prototype = combinators_v1.get_trigger_mine_prototype(custom_event_name, effect_id)
```

## Client Methods

### combinators_v1.create_invisible_raw
Create an invisible device directly by prototype name using `LuaSurface.create_entity`.

This bypasses the combinator registration database and uses the exact prototype you provide.

```lua
---@param surface LuaSurface The surface to create the invisible device on.
---@param prototype_name string The exact prototype name to create.
---@param create_args table Arguments passed to `LuaSurface.create_entity`. Some fields are overridden to enforce invisible-device behavior.
---@return LuaEntity? invisible_device The created invisible device entity, or nil if creation failed.
local invisible_device = combinators_v1.create_invisible_raw(surface, prototype_name, create_args)
```

### combinators_v1.create_invisible
Create an invisible device from a registered base combinator name.

```lua
---@param surface LuaSurface The surface to create the invisible device on.
---@param base_name string The registered base combinator name.
---@param is_powered boolean If true, the powered variant is used when available.
---@param create_args table Arguments passed to `LuaSurface.create_entity`. Some fields are overridden to enforce invisible-device behavior.
---@return string? err Error message if creation failed.
---@return LuaEntity? invisible_device The created invisible device entity, or nil if creation failed.
local err, invisible_device = combinators_v1.create_invisible(surface, base_name, is_powered, create_args)
```
