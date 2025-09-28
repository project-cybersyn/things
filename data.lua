---@class things.EventData.on_unthing_built
---@field public entity LuaEntity The entity that was built. May be a ghost or real entity.
---@field public prototype_name string The resolved `name` or `ghost_name` of the entity.
---@field public prototype_type string The resolved `type` or `ghost_type` of the entity.

---@class things.EventData.on_tags_changed
---@field public thing_id int The id of the Thing whose tags changed.
---@field public entity LuaEntity? The current entity of the Thing, if it has one.
---@field public new_tags Tags The new tags of the Thing.
---@field public previous_tags Tags The previous tags of the Thing.
data:extend({
	{ type = "custom-event", name = "things-on_unthing_built" },
	{ type = "custom-event", name = "things-on_thing_lifecycle" },
	{ type = "custom-event", name = "things-on_tags_changed" },
})
