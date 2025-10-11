-- Convert internal events into custom Factorio events as appropriate.

local bind = require("control.events.typed").bind
local tlib = require("lib.core.table")

local EMPTY = tlib.EMPTY_STRICT

bind("thing_initialized", function(thing)
	local cevp = thing:get_custom_event_name("on_initialized")
	if not cevp then return end

	---@type things.EventData.on_initialized
	local ev = thing:summarize()
	script.raise_event(cevp, ev)
end)

bind("thing_status", function(thing, old_status)
	local cevp = thing:get_custom_event_name("on_status")
	if not cevp then return end

	---@type things.EventData.on_status
	local ev = {
		thing = thing:summarize(),
		old_status = old_status,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_tags_changed", function(thing, old_tags)
	local cevp = thing:get_custom_event_name("on_tags_changed")
	if not cevp then return end

	---@type things.EventData.on_tags_changed
	local ev = {
		thing = thing:summarize(),
		previous_tags = old_tags,
		new_tags = thing.tags,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_edges_changed", function(thing, graph_name, change, nodes, edges)
	local cevp = thing:get_custom_event_name("on_edges_changed")
	if not cevp then return end

	---@type things.EventData.on_edges_changed
	local ev = {
		change = change,
		graph_name = graph_name,
		nodes = nodes,
		edges = edges,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_virtual_orientation_changed", function(thing, old_orientation)
	local cevp = thing:get_custom_event_name("on_orientation_changed")
	if not cevp then return end

	local summary = thing:summarize()
	---@type things.EventData.on_orientation_changed
	local ev = {
		thing = summary,
		old_orientation = old_orientation and old_orientation:to_data(),
		new_orientation = summary.virtual_orientation,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_children_changed", function(thing, added, removed)
	local cevp = thing:get_custom_event_name("on_children_changed")
	if not cevp then return end

	---@type things.EventData.on_children_changed
	local ev = {
		thing = thing:summarize(),
		added = added and added:summarize(),
		removed = removed
			and tlib.map(removed, function(c) return c:summarize() end),
	}
	script.raise_event(cevp, ev)
end)

bind("thing_parent_changed", function(thing, old_parent_id)
	local cevp = thing:get_custom_event_name("on_parent_changed")
	if not cevp then return end

	---@type things.EventData.on_parent_changed
	local ev = {
		thing = thing:summarize(),
		old_parent_id = old_parent_id,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_child_status", function(parent, child, old_status)
	local cevp = parent:get_custom_event_name("on_child_status")
	if not cevp then return end

	---@type things.EventData.on_child_status
	local ev = {
		thing = parent:summarize(),
		child = child:summarize(),
		old_status = old_status,
	}
	script.raise_event(cevp, ev)
end)

bind("thing_parent_status", function(thing, parent, old_status)
	local cevp = thing:get_custom_event_name("on_parent_status")
	if not cevp then return end

	---@type things.EventData.on_parent_status
	local ev = {
		thing = thing:summarize(),
		parent = parent:summarize(),
		old_status = old_status,
	}
	script.raise_event(cevp, ev)
end)
