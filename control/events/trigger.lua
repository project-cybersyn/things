local events = require("lib.core.event")
local registry = require("control.registration")
local tlib = require("lib.core.table")

local EMPTY = tlib.EMPTY
local get_thing_registration = registry.get_thing_registration

events.bind(
	defines.events.on_script_trigger_effect,
	---@param ev EventData.on_script_trigger_effect
	function(ev)
		if ev.effect_id ~= "things-trigger" then return end
		local trigger = ev.source_entity
		if not trigger then return end
		local trigger_id = trigger.unit_number --[[@as UnitNumber]]
		local trigger_info = storage.trigger_entities[trigger_id]
		if not trigger_info then
			-- TODO: consider destroying trigger device here?
			return
		end
		local thing = storage.things[trigger_info.thing_id or 0]
		if not thing then
			-- TODO: consider destroying trigger device here?
			return
		end
		local reg = get_thing_registration(thing.name)
		if (not reg) or not reg.custom_events then return nil end
		local cevp = reg.custom_events["on_trigger"]
		if cevp then
			script.raise_event(cevp, {
				thing_id = thing.id,
				trigger_id = trigger_id,
				trigger_data = trigger_info.trigger_data,
			})
		end
	end
)
