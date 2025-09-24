---@class things.EventData.on_unthing_built
---@field public entity LuaEntity The entity that was built. May be a ghost or real entity.
---@field public prototype_name string The resolved `name` or `ghost_name` of the entity.
---@field public prototype_type string The resolved `type` or `ghost_type` of the entity.

data:extend({
	{ type = "custom-event", name = "things-on_unthing_built" },
	{ type = "custom-event", name = "things-on_thing_lifecycle" },
})
