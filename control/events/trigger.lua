local events = require("lib.core.event")
local registry = require("control.registration")
local tlib = require("lib.core.table")

local EMPTY = tlib.EMPTY
local get_thing_registration = registry.get_thing_registration
local script_raise_event = script.raise_event

local _trigger_ev_cache = {}

---@param thing_name string
---@return LuaCustomEventPrototype? cevp_prototype
local function get_trigger_event_prototype(thing_name)
	local cached = _trigger_ev_cache[thing_name]
	if cached then
		if cached == EMPTY then return nil end
		return cached
	end
	local reg = get_thing_registration(thing_name)
	if not reg then
		_trigger_ev_cache[thing_name] = EMPTY
		return nil
	end
	if not reg.custom_events then
		_trigger_ev_cache[thing_name] = EMPTY
		return nil
	end
	local cevp_name = reg.custom_events["on_trigger"]
	if not cevp_name then
		_trigger_ev_cache[thing_name] = EMPTY
		return nil
	end
	local cevp_prototype = prototypes.custom_event[cevp_name]
	if not cevp_prototype then
		_trigger_ev_cache[thing_name] = EMPTY
		return nil
	end

	_trigger_ev_cache[thing_name] = cevp_prototype
	return cevp_prototype
end

events.bind(
	"things-trigger",
	---@param ev EventData.on_script_trigger_effect
	function(ev)
		-- Retrieve trigger info
		local trigger = ev.source_entity
		if not trigger then return end
		local trigger_id = trigger.unit_number --[[@as UnitNumber]]
		local trigger_info = storage.trigger_entities[trigger_id]
		if not trigger_info then
			-- TODO: consider destroying trigger device here?
			return
		end

		-- Collapse out double fired triggers
		local t = game.tick
		local last_fired_tick = trigger_info.fired_tick
		trigger_info.fired_tick = t
		if (last_fired_tick or 0) ~= (t - 1) then return end

		-- Debounce
		local t0 = trigger_info.trigger_after or 0
		if t <= t0 then return end
		local dt = trigger_info.debounce_ticks
		if dt then trigger_info.trigger_after = t + dt end

		-- Locate and notify trigger target.
		local thing = storage.things[trigger_info.thing_id or 0]
		if not thing then
			-- TODO: consider destroying trigger device here?
			return
		end

		local cevp = get_trigger_event_prototype(thing.name)
		if cevp then
			script_raise_event(cevp, {
				thing_id = thing.id,
				trigger_id = trigger_id,
				trigger_data = trigger_info.trigger_data,
			})
		end
	end
)
