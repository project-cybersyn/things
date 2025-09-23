---@class things.EventData.on_unthing_built
---@field public entity LuaEntity The entity that was built. May be a ghost or real entity.

data:extend({
	{ type = "custom-event", name = "things-on_unthing_built" },
	{ type = "custom-event", name = "things-on_thing_lifecycle" },
})
