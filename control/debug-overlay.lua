local MultiLineTextOverlay = require("lib.core.overlay").MultiLineTextOverlay
local events = require("lib.core.event")
local orientation_lib = require("lib.core.orientation.orientation")

---@alias things.DebugOverlay Core.MultiLineTextOverlay

local state_icons = {
	real = "[virtual-signal=signal-lightning]",
	ghost = "[virtual-signal=signal-ghost]",
	tombstone = "[virtual-signal=signal-recycle]",
	destroyed = "[virtual-signal=signal-skull]",
}

---@param thing things.Thing
local function update_overlay(thing)
	local thing_id = thing.id
	local debug_overlay = storage.debug_overlays[thing_id]
	if not debug_overlay then return end
	local lines = {
		string.format("%s %s", thing.id, state_icons[thing.state] or "?"),
	}
	if thing.parent then
		table.insert(
			lines,
			string.format("C%s/%d", thing.parent[2], thing.parent[1])
		)
	end
	local O = thing:get_orientation()
	if O then table.insert(lines, orientation_lib.stringify(O)) end
	-- XXX: remove this
	if thing.tags and thing.tags.clicker then
		table.insert(lines, "Clicker: " .. thing.tags.clicker)
	end
	debug_overlay:set_text(lines)
end

local function recreate_overlay(thing)
	local thing_id = thing.id
	local debug_overlay = storage.debug_overlays[thing_id]
	if debug_overlay then
		debug_overlay:destroy()
		storage.debug_overlays[thing_id] = nil
	end
	if thing.entity and thing.entity.valid and mod_settings.debug then
		debug_overlay = MultiLineTextOverlay:new(
			thing.entity.surface,
			{ entity = thing.entity },
			3,
			0.6
		)
		storage.debug_overlays[thing_id] = debug_overlay
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
	for id, overlay in pairs(storage.debug_overlays) do
		overlay:destroy()
		storage.debug_overlays[id] = nil
	end
end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

events.bind("on_mod_settings_changed", function()
	if mod_settings.debug then
		rebuild_overlays()
	else
		clear_overlays()
	end
end)

events.bind("things.thing_status", function(thing, old_state)
	if mod_settings.debug then rebuild_overlay(thing) end
end)

events.bind("things.thing_tags_changed", function(thing, tags, previous_tags)
	if mod_settings.debug then update_overlay(thing) end
end)

events.bind("things.thing_initialized", function(thing)
	if mod_settings.debug then rebuild_overlay(thing) end
end)

events.bind("things.thing_parent_changed", function(thing, old_parent_id)
	if mod_settings.debug then update_overlay(thing) end
end)

events.bind("things.thing_children_changed", function(thing, child, added)
	if mod_settings.debug then update_overlay(thing) end
end)

events.bind(
	"things.thing_orientation_changed",
	function(thing, new_orientation, old_orientation)
		if mod_settings.debug then update_overlay(thing) end
	end
)
