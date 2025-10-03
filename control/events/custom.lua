-- Convert internal events into custom Factorio events as appropriate.

local bind = require("control.events.typed").bind

bind(
	"thing_initialized",
	function(thing)
		script.raise_event(
			"things-on_initialized",
			{ thing_id = thing.id, entity = thing.entity, status = thing.state }
		)
	end
)

bind(
	"thing_status",
	function(thing, old_status)
		script.raise_event("things-on_status_changed", {
			thing_id = thing.id,
			entity = thing.entity,
			new_status = thing.state,
			old_status = old_status,
			cause = thing.state_cause,
		})
	end
)

bind(
	"thing_tags_changed",
	function(thing, old_tags)
		script.raise_event("things-on_tags_changed", {
			thing_id = thing.id,
			entity = thing.entity,
			previous_tags = old_tags,
			new_tags = thing.tags,
		})
	end
)

bind(
	"thing_edges_changed",
	function(thing, graph_name, change, nodes, edges)
		script.raise_event("things-on_edges_changed", {
			change = change,
			graph_name = graph_name,
			nodes = nodes,
			edges = edges,
		})
	end
)
