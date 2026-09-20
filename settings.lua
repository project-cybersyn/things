--------------------------------------------------------------------------------
-- THINGS SETTINGS PHASE
--------------------------------------------------------------------------------

data:extend({
	{
		type = "string-setting",
		name = "things-setting-log-level",
		order = "a",
		setting_type = "runtime-global",
		default_value = "NONE",
		allowed_values = { "NONE", "WARN", "INFO", "DEBUG", "TRACE" },
	},
	{
		type = "bool-setting",
		name = "things-setting-debug",
		order = "aa",
		setting_type = "runtime-global",
		default_value = false,
	},
	{
		type = "bool-setting",
		name = "things-setting-debug-render-blueprint-bboxes",
		order = "ab",
		setting_type = "runtime-global",
		default_value = false,
	},
	{
		type = "bool-setting",
		name = "things-setting-debug-calc-unthing-blueprints",
		order = "ac",
		setting_type = "runtime-global",
		default_value = false,
	},
	{
		type = "bool-setting",
		name = "things-setting-debug-always-splice",
		order = "ad",
		setting_type = "runtime-global",
		default_value = false,
	},
})
