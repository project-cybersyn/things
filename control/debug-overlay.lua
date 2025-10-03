local MultiLineTextOverlay = require("lib.core.overlay").MultiLineTextOverlay
local bind = require("control.events.typed").bind

---@param thing things.Thing
local function update_overlay(thing)
	if not thing.debug_overlay then return end
	local lines = {
		"Thing " .. thing.id,
		thing.state,
	}
	-- XXX: remove this
	if thing.tags and thing.tags.clicker then
		table.insert(lines, "Clicker: " .. thing.tags.clicker)
	end
	thing.debug_overlay:set_text(lines)
end

local function recreate_overlay(thing)
	if thing.debug_overlay then
		thing.debug_overlay:destroy()
		thing.debug_overlay = nil
	end
	if thing.entity and thing.entity.valid and mod_settings.debug then
		thing.debug_overlay = MultiLineTextOverlay:new(
			thing.entity.surface,
			{ entity = thing.entity },
			4,
			0.6
		)
	end
end

local function rebuild_overlay(thing)
	recreate_overlay(thing)
	update_overlay(thing)
end

local function rebuild_overlays()
	for _, thing in pairs(storage.things) do
		rebuild_overlay(thing)
	end
end

local function clear_overlays()
	for _, thing in pairs(storage.things) do
		if thing.debug_overlay then
			thing.debug_overlay:destroy()
			thing.debug_overlay = nil
		end
	end
end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

bind("mod_settings_changed", function()
	if mod_settings.debug then
		rebuild_overlays()
	else
		clear_overlays()
	end
end)

bind("thing_status", function(thing, old_state)
	if mod_settings.debug then rebuild_overlay(thing) end
end)

bind("thing_tags_changed", function(thing, previous_tags)
	if mod_settings.debug then update_overlay(thing) end
end)
