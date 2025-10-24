-- Event processing downstream from core frames.
local events = require("lib.core.event")
local registry = require("control.registration")

local get_thing_registration = registry.get_thing_registration

local function get_custom_event_name(thing, subevent)
	local reg = get_thing_registration(thing.name)
	if (not reg) or not reg.custom_events then return nil end
	return reg.custom_events[subevent]
end

events.bind(
	"things.thing_initialized",
	---@param thing things.Thing
	function(thing)
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
