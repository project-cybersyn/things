local events = require("lib.core.event")

---@class (exact) things.ModSettings
---@field public debug boolean Enable debug mode.

---@type things.ModSettings
---@diagnostic disable-next-line: missing-fields
local mod_settings = {}
_G.mod_settings = mod_settings

local function update_mod_settings()
	mod_settings.debug = settings.global["things-setting-debug"].value --[[@as boolean]]
end

update_mod_settings()

events.bind(
	"on_startup",
	function() events.raise("on_mod_settings_changed") end
)

events.bind(
	defines.events.on_runtime_mod_setting_changed,
	---@param event EventData.on_runtime_mod_setting_changed
	function(event)
		update_mod_settings()
		events.raise("on_mod_settings_changed", event.setting)
	end
)
