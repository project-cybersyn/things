--------------------------------------------------------------------------------
-- THINGS DATA PHASE
--------------------------------------------------------------------------------

-- Bootstrap Relm data phase
_G.__RELM_GRAPHICS_PATH__ = "__0-things__/lib/core/relm/graphics/"
require("lib.core.relm.relm_data")

data:extend({
	{ type = "mod-data", name = "things-names", data = {} },
	{ type = "mod-data", name = "things-graphs", data = {} },
	{ type = "mod-data", name = "things-combinators", data = {} },
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
})

require("data.combinators")

-- Force Cooperative Blueprinting host to Things.
data:extend({
	{
		type = "mod-data",
		name = "cooperative-blueprinting",
		data = { host_name = "0-things", host_protocol_version = 1 },
	},
	{
		type = "custom-event",
		name = "cooperative-blueprinting-v1-on_pre_build_blueprint",
	},
	{
		type = "custom-event",
		name = "cooperative-blueprinting-v1-on_pre_extract",
	},
	{ type = "custom-event", name = "cooperative-blueprinting-v1-on_extract" },
	{
		type = "custom-event",
		name = "cooperative-blueprinting-v1-on_post_extract",
	},
})
log({
	"",
	"Things: stealing Cooperative Blueprinting host: host set to '0-things'",
})
