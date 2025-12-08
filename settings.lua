--------------------------------------------------------------------------------
-- THINGS SETTINGS PHASE
--------------------------------------------------------------------------------

data:extend({
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
})
