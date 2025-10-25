---
sidebar_position: 1
---

# Registering Things

Things are registered during Factorio's data phase by adding information to the `mod-data` prototype named `things-names`.

```lua
---@type things.ThingRegistration
local mux_registration = {
	name = "ribbon-cables-mux",
	intercept_construction = true,
	virtualize_orientation = oc_lib.OrientationClass.OC_048CM_RF,
	custom_events = {
		on_initialized = "ribbon-cables-on_initialized",
		on_status = "ribbon-cables-on_status",
		on_edge_status = "ribbon-cables-on_edge_status",
		on_children_normalized = "ribbon-cables-on_children_normalized",
	},
	children = {
		[1] = {
			create = { name = "ribbon-cables-pin", position = { 0, 0 } },
			offset = { -2, -2 },
		},
		[2] = {
			create = { name = "ribbon-cables-pin", position = { 0, 0 } },
			offset = { 0, -2 },
		},
	},
}
data.raw["mod-data"]["things-names"].data["ribbon-cables-mux"] =
	mux_registration
```
