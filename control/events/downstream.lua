-- Event processing downstream from core frames.
local events = require("lib.core.event")
local registry = require("control.registration")
local tlib = require("lib.core.table")

local get_thing_registration = registry.get_thing_registration

local function get_custom_event_name(thing, subevent)
	local reg = get_thing_registration(thing.name)
	if (not reg) or not reg.custom_events then return nil end
	return reg.custom_events[subevent]
end

local function get_graph_custom_event_name(graph, subevent)
	local reg = registry.get_graph_registration(graph.name)
	if (not reg) or not reg.custom_events then return nil end
	return reg.custom_events[subevent]
end

events.bind(
	"things.thing_initialized",
	---@param thing things.Thing
	function(thing)
		thing:apply_adjusted_pos_and_orientation()
		thing.is_silent = false
		local cevp = get_custom_event_name(thing, "on_initialized")

		if cevp then
			---@type things.EventData.on_initialized
			local ev = thing:summarize()
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_status",
	---@param thing things.Thing
	function(thing, old_status)
		local cevp = get_custom_event_name(thing, "on_status")
		if cevp then
			---@type things.EventData.on_status
			local ev = {
				thing = thing:summarize(),
				new_status = thing.state,
				old_status = old_status,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_orientation_changed",
	---@param thing things.Thing
	function(thing, new_orientation, old_orientation)
		local cevp = get_custom_event_name(thing, "on_orientation_changed")
		if cevp then
			---@type things.EventData.on_orientation_changed
			local ev = {
				thing = thing:summarize(),
				new_orientation = new_orientation,
				old_orientation = old_orientation,
			}
			script.raise_event(cevp, ev)
		end
		-- Apply child orientations
		if thing.children then
			for _, child_id in pairs(thing.children) do
				local child_thing = get_thing_by_id(child_id)
				if child_thing then child_thing:apply_adjusted_pos_and_orientation() end
			end
		end
	end
)

events.bind(
	"things.thing_position_changed",
	---@param thing things.Thing
	function(thing, new_position, old_position)
		local cevp = get_custom_event_name(thing, "on_position_changed")
		if cevp then
			---@type things.EventData.on_position_changed
			local ev = {
				thing = thing:summarize(),
				new_position = new_position,
				old_position = old_position,
			}
			script.raise_event(cevp, ev)
		end
		-- Apply child positions
		if thing.children then
			for _, child_id in pairs(thing.children) do
				local child_thing = get_thing_by_id(child_id)
				if child_thing then child_thing:apply_adjusted_pos_and_orientation() end
			end
		end
	end
)

events.bind(
	"things.thing_tags_changed",
	---@param thing things.Thing
	function(thing, new_tags, old_tags)
		local cevp = get_custom_event_name(thing, "on_tags_changed")
		if cevp then
			---@type things.EventData.on_tags_changed
			local ev = {
				thing = thing:summarize(),
				new_tags = new_tags,
				old_tags = old_tags,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_parent_changed",
	---@param thing things.Thing
	---@param new_parent things.Thing|nil
	function(thing, new_parent)
		thing:apply_adjusted_pos_and_orientation()

		local cevp = get_custom_event_name(thing, "on_parent_changed")
		if cevp then
			---@type things.EventData.on_parent_changed
			local ev = {
				thing = thing:summarize(),
				new_parent = new_parent and new_parent:summarize(),
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_children_changed",
	---@param thing things.Thing
	---@param added_child things.Thing|nil
	---@param removed_children things.Thing[]|nil
	function(thing, added_child, removed_children)
		local cevp = get_custom_event_name(thing, "on_children_changed")
		if cevp then
			---@type things.EventData.on_children_changed
			local ev = {
				thing = thing:summarize(),
				added = added_child and added_child:summarize(),
				removed = nil,
			}
			if removed_children then
				ev.removed = tlib.map(
					removed_children,
					---@param rc things.Thing
					function(rc) return rc:summarize() end
				)
			end
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_parent_status",
	function(thing, parent, old_parent_status)
		local cevp = get_custom_event_name(thing, "on_parent_status")
		if cevp then
			---@type things.EventData.on_parent_status
			local ev = {
				thing = thing:summarize(),
				parent = parent:summarize(),
				old_parent_status = old_parent_status,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_child_status",
	function(thing, child, child_index, old_child_status)
		local cevp = get_custom_event_name(thing, "on_child_status")
		if cevp then
			---@type things.EventData.on_child_status
			local ev = {
				thing = thing:summarize(),
				child = child:summarize(),
				child_index = child_index,
				old_child_status = old_child_status,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_immediate_voided",
	---@param thing things.Thing
	function(thing)
		local cevp = get_custom_event_name(thing, "on_immediate_voided")
		if cevp then
			---@type things.EventData.on_immediate_voided
			local ev = thing:summarize()
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.graph_add_edge",
	---@param graph things.Graph
	---@param edge things.GraphEdge
	---@param from things.Thing
	---@param to things.Thing
	function(graph, edge, from, to)
		local cevp = get_graph_custom_event_name(graph, "on_edge_changed")
		if cevp then
			---@type things.EventData.on_edge_changed
			local ev = {
				change = "create",
				graph_name = graph.name,
				edge = edge,
				from = from:summarize(),
				to = to:summarize(),
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.graph_remove_edge",
	---@param graph things.Graph
	---@param edge things.GraphEdge
	---@param from things.Thing
	---@param to things.Thing
	function(graph, edge, from, to)
		local cevp = get_graph_custom_event_name(graph, "on_edge_changed")
		if cevp then
			---@type things.EventData.on_edge_changed
			local ev = {
				change = "delete",
				graph_name = graph.name,
				edge = edge,
				from = from:summarize(),
				to = to:summarize(),
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.graph_set_edge_data",
	---@param graph things.Graph
	---@param edge things.GraphEdge
	---@param from things.Thing
	---@param to things.Thing
	function(graph, edge, from, to)
		local cevp = get_graph_custom_event_name(graph, "on_edge_changed")
		if cevp then
			---@type things.EventData.on_edge_changed
			local ev = {
				change = "set-data",
				graph_name = graph.name,
				edge = edge,
				from = from:summarize(),
				to = to:summarize(),
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_edge_status",
	function(thing, changed_thing, graph, edge, old_status)
		local cevp = get_custom_event_name(thing, "on_edge_status")
		if cevp then
			---@type things.EventData.on_edge_status
			local ev = {
				thing = thing:summarize(),
				changed_thing = changed_thing:summarize(),
				graph_name = graph.name,
				edge = edge,
				old_status = old_status,
				new_status = changed_thing.state,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_children_normalized",
	---@param thing things.Thing
	function(thing)
		local cevp = get_custom_event_name(thing, "on_children_normalized")
		if cevp then
			---@type things.EventData.on_children_normalized
			local ev = thing:summarize()
			script.raise_event(cevp, ev)
		end
	end
)
