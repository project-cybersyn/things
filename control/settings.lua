local events = require("lib.core.event")

---@class (exact) things.ModSettings
---@field public debug boolean Enable debug mode.
---@field public render_blueprint_bboxes boolean Whether to render blueprint entity bounding boxes for debugging.
---@field public calc_unthing_blueprints boolean Whether to calculate geometry for blueprints with no Things for debugging.
---@field public always_splice boolean Whether to always splice blueprints when Things is the Cooperative Blueprinting Host.

---@type things.ModSettings
---@diagnostic disable-next-line: missing-fields
local l_mod_settings = {}
mod_settings = l_mod_settings

local function update_mod_settings()
	l_mod_settings.debug = settings.global["things-setting-debug"].value --[[@as boolean]]
	l_mod_settings.render_blueprint_bboxes =
		settings.global["things-setting-debug-render-blueprint-bboxes"].value --[[@as boolean]]
	l_mod_settings.calc_unthing_blueprints =
		settings.global["things-setting-debug-calc-unthing-blueprints"].value --[[@as boolean]]
	l_mod_settings.always_splice =
		settings.global["things-setting-debug-always-splice"].value --[[@as boolean]]
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
