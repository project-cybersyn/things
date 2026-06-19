--------------------------------------------------------------------------------
-- THINGS DATA PHASE
--------------------------------------------------------------------------------

-- Bootstrap Relm data phase
_G.__RELM_GRAPHICS_PATH__ = "__0-things__/lib/core/relm/graphics/"
require("lib.core.relm.relm_data")

data:extend({
	{ type = "mod-data", name = "things-names", data = {} },
	{ type = "mod-data", name = "things-graphs", data = {} },
	{
		type = "custom-input",
		name = "things-linked-rotate",
		key_sequence = "",
		linked_game_control = "rotate",
	},
	{
		type = "custom-input",
		name = "things-linked-reverse-rotate",
		key_sequence = "",
		linked_game_control = "reverse-rotate",
	},
	{
		type = "custom-input",
		name = "things-linked-flip-horizontal",
		key_sequence = "",
		linked_game_control = "flip-horizontal",
	},
	{
		type = "custom-input",
		name = "things-linked-flip-vertical",
		key_sequence = "",
		linked_game_control = "flip-vertical",
	},
	{
		type = "custom-event",
		name = "things-cooperative_blueprint_edit",
	},
})
