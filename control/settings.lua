---@class (exact) things.ModSettings
---@field public debug boolean Enable debug mode.
---@field public work_period uint Number of ticks between work cycles.
---@field public work_factor number Multiplier applied to work done per cycle.

---@type things.ModSettings
---@diagnostic disable-next-line: missing-fields
local mod_settings = {}
_G.mod_settings = mod_settings

local function update_mod_settings()
	mod_settings.debug = settings.global["things-setting-debug"].value --[[@as boolean]]
end
_G.update_mod_settings = update_mod_settings

update_mod_settings()
on_startup(function() raise_mod_settings_changed() end)
