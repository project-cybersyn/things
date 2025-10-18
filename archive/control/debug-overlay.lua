local MultiLineTextOverlay = require("lib.core.overlay").MultiLineTextOverlay
local bind = require("control.events.typed").bind

local state_icons = {
	real = "[virtual-signal=signal-lightning]",
	ghost = "[virtual-signal=signal-ghost]",
	tombstone = "[virtual-signal=signal-recycle]",
	destroyed = "[virtual-signal=signal-skull]",
}

---@param thing things.Thing
local function update_overlay(thing)
	if not thing.debug_overlay then return end
	local lines = {
		string.format("%s %s", thing.id, state_icons[thing.state] or "?"),
	}
	if thing.parent then
		table.insert(
			lines,
			string.format("C%s/%d", thing.child_key_in_parent, thing.parent.id)
		)
	end
	if thing.tags and thing.tags["@o"] then
		table.insert(
			lines,
			"O: " .. serpent.line(thing.tags["@o"], { nocode = true })
		)
	end
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
			3,
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

bind("thing_initialized", function(thing)
	if mod_settings.debug then rebuild_overlay(thing) end
end)

bind("thing_parent_changed", function(thing, old_parent_id)
	if mod_settings.debug then update_overlay(thing) end
end)

bind("thing_children_changed", function(thing, child, added)
	if mod_settings.debug then update_overlay(thing) end
end)
