-- Event processing downstream from core frames.
local events = require("lib.core.event")
local registry = require("control.registration")
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")

local type = type
local pairs = pairs
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
	---@param from_blueprint boolean? If true, this Thing was initialized from a blueprint.
	function(thing, from_blueprint)
		if not thing:is_valid() then return end
		thing:reorient(true)
		thing.is_silent = false
		local cevp = get_custom_event_name(thing, "on_initialized")

		if cevp then
			local ev = thing:summarize() --[[@as things.EventData.on_initialized ]]
			-- The "name" arg gets overwritten by Factorio when raising the event, so we need to put it in a different field and rename it before raising the event.
			ev.thing_name = ev.name --[[@as string ]]
			ev.from_blueprint = from_blueprint
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
				thing = thing:summarize_short(),
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
		-- Apply child orientations
		thing:reorient(false, true)

		-- Raise event
		local cevp = get_custom_event_name(thing, "on_orientation_changed")
		if cevp then
			---@type things.EventData.on_orientation_changed
			local ev = {
				thing = thing:summarize_short(),
				new_orientation = new_orientation,
				old_orientation = old_orientation,
			}
			script.raise_event(cevp, ev)
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
				thing = thing:summarize_short(),
				new_position = new_position,
				old_position = old_position,
			}
			script.raise_event(cevp, ev)
		end

		thing:reorient(false, true)
	end
)

events.bind(
	"things.thing_tags_changed",
	---@param thing things.Thing
	---@param new_tags Tags
	---@param old_tags Tags
	---@param cause "api"|"engine"
	function(thing, new_tags, old_tags, cause)
		local cevp = get_custom_event_name(thing, "on_tags_changed")
		if cevp then
			---@type things.EventData.on_tags_changed
			local ev = {
				thing = thing:summarize_short(),
				new_tags = new_tags,
				old_tags = old_tags,
				cause = cause,
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
		strace.trace("Reorienting Thing ID", thing.id, "due to parent change.")
		thing:reorient()

		local cevp = get_custom_event_name(thing, "on_parent_changed")
		if cevp then
			---@type things.EventData.on_parent_changed
			local ev = {
				thing = thing:summarize_short(),
				new_parent = new_parent and new_parent:summarize_short(),
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_children_changed",
	---@param thing things.Thing
	---@param added_child things.Thing | LuaEntity | nil
	---@param removed_children (things.Thing|LuaEntity)[] | nil
	function(thing, added_child, removed_children)
		local cevp = get_custom_event_name(thing, "on_children_changed")
		if cevp then
			local added
			if type(added_child) == "table" then
				added = added_child.id
			elseif added_child then
				added = added_child
			end

			---@type things.EventData.on_children_changed
			local ev = {
				thing = thing:summarize_short(),
				added = added,
				removed = nil,
			}
			if removed_children then
				ev.removed = tlib.map(removed_children, function(rc)
					if type(rc) == "table" then
						return rc.id
					else
						return rc --[[@as LuaEntity]]
					end
				end)
			end
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_parent_status",
	---@param thing things.Thing
	---@param parent things.Thing
	---@param old_parent_status things.Status
	function(thing, parent, old_parent_status)
		local cevp = get_custom_event_name(thing, "on_parent_status")
		if cevp then
			---@type things.EventData.on_parent_status
			local ev = {
				thing = thing:summarize_short(),
				parent = parent:summarize_short(),
				old_parent_status = old_parent_status,
			}
			script.raise_event(cevp, ev)
		end
	end
)

events.bind(
	"things.thing_child_status",
	---@param thing things.Thing
	---@param child things.Thing
	---@param child_index string
	---@param old_child_status things.Status
	function(thing, child, child_index, old_child_status)
		local cevp = get_custom_event_name(thing, "on_child_status")
		if cevp then
			---@type things.EventData.on_child_status
			local ev = {
				thing = thing:summarize_short(),
				child = child:summarize_short(),
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
			local ev = { thing = thing:summarize_short() }
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
				from = from:summarize_short(),
				to = to:summarize_short(),
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
				from = from:summarize_short(),
				to = to:summarize_short(),
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
				from = from:summarize_short(),
				to = to:summarize_short(),
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
				thing = thing:summarize_short(),
				changed_thing = changed_thing:summarize_short(),
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
			local short_summary = thing:summarize_short()
			---@type things.EventData.on_children_normalized
			local ev = { thing = short_summary, entity = thing.entity }
			script.raise_event(cevp, ev)
		end
	end
)
