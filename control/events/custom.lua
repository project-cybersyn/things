-- Convert internal events into custom Factorio events as appropriate.

local bind = require("control.events.typed").bind

bind("thing_initialized", function(thing)
	---@type things.EventData.on_initialized
	local ev = thing:summarize()
	script.raise_event("things-on_initialized", ev)
end)

bind("thing_status", function(thing, old_status)
	---@type things.EventData.on_status_changed
	local ev = {
		thing = thing:summarize(),
		new_status = thing.state --[[@as things.Status]],
		old_status = old_status,
		cause = thing.state_cause,
	}
	script.raise_event("things-on_status_changed", ev)
end)

bind("thing_tags_changed", function(thing, old_tags)
	---@type things.EventData.on_tags_changed
	local ev = {
		thing = thing:summarize(),
		previous_tags = old_tags,
		new_tags = thing.tags,
	}
	script.raise_event("things-on_tags_changed", ev)
end)

bind("thing_edges_changed", function(thing, graph_name, change, nodes, edges)
	---@type things.EventData.on_edges_changed
	local ev = {
		change = change,
		graph_name = graph_name,
		nodes = nodes,
		edges = edges,
	}
	script.raise_event("things-on_edges_changed", ev)
end)

bind("thing_virtual_orientation_changed", function(thing, old_orientation)
	local summary = thing:summarize()
	---@type things.EventData.on_orientation_changed
	local ev = {
		thing = summary,
		old_orientation = old_orientation and old_orientation:to_data(),
		new_orientation = summary.virtual_orientation,
	}
	script.raise_event("things-on_orientation_changed", ev)
end)
