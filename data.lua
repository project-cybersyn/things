data:extend({
	{ type = "custom-event", name = "things-on_initialized" },
	{ type = "custom-event", name = "things-on_status_changed" },
	{ type = "custom-event", name = "things-on_tags_changed" },
	{ type = "custom-event", name = "things-on_edges_changed" },
	{ type = "mod-data", name = "things-names", data = {} },
	{ type = "mod-data", name = "things-graphs", data = {} },
	{
		type = "custom-input",
		name = "things-linked-undo",
		key_sequence = "",
		linked_game_control = "undo",
	},
})
