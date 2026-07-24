-- Internal remote interface.
-- These methods are intended to be called by the Client and are considered undocumented.
-- There are no stability guarantees for these methods, and they may change or be removed at any time.

local thing_lib = require("control.thing")

---@type things.Storage
storage = storage --[[@as things.Storage]]

local get_thing_by_unit_number = thing_lib.get_by_unit_number

local api = {}

---@param thing_id things.Id?
function api.get(thing_id)
	local thing = storage.things[thing_id or 0]
	if not thing then return nil end
	return thing:summarize_short()
end

---@param entity ValidEntity
function api.get_thing_id(entity)
	local thing = get_thing_by_unit_number(entity.unit_number)
	if not thing then return nil end
	return thing.id
end

---@param trigger_id things.Id?
---@param trigger_info things.TriggerInfo?
function api.set_trigger_info(trigger_id, trigger_info)
	if not trigger_id then return end
	if not trigger_info then
		storage.trigger_entities[trigger_id] = nil
	else
		storage.trigger_entities[trigger_id] = trigger_info
		local entity = trigger_info.entity
		if entity and entity.valid then
			script.register_on_object_destroyed(entity)
		end
	end
end

---@param trigger_id things.Id?
---@param is_armed boolean
---@return boolean success
function api.set_trigger_armed(trigger_id, is_armed)
	if not trigger_id then return false end
	local trigger_info = storage.trigger_entities[trigger_id]
	if not trigger_info then return false end
	local entity = trigger_info.entity
	if not entity or not entity.valid then return false end
	if is_armed then
		entity.disabled_by_script = false
	else
		entity.disabled_by_script = true
	end

	return true
end

---@param trigger_id things.Id?
---@return things.Id? triggered_parent
function api.check_trigger(trigger_id)
	if not trigger_id then return nil end
	local trigger_info = storage.trigger_entities[trigger_id]
	if not trigger_info then return nil end

	-- Collapse out double fired triggers
	local t = game.tick
	local last_fired_tick = trigger_info.fired_tick
	trigger_info.fired_tick = t
	if (last_fired_tick or 0) ~= (t - 1) then return nil end

	-- Debounce
	local t0 = trigger_info.trigger_after or 0
	if t <= t0 then return nil end
	local dt = trigger_info.debounce_ticks
	if dt then trigger_info.trigger_after = t + dt end

	return trigger_info.thing_id
end

---@param thing_id things.Id?
---@param child_index string
---@param child LuaEntity
---@param relative_pos MapPosition?
---@param relative_orientation Core.Dihedral?
---@return boolean child_was_added
function api.add_unthing_child(
	thing_id,
	child_index,
	child,
	relative_pos,
	relative_orientation
)
	local thing = storage.things[thing_id or 0]
	if not thing then return false end
	return thing:add_child(child_index, child, relative_pos, relative_orientation)
end

---@param thing_id things.Id?
---@param child_key string
---@param destroy_child boolean
function api.remove_child(thing_id, child_key, destroy_child)
	local thing = storage.things[thing_id or 0]
	if not thing then return false end
	return thing:remove_child(child_key, destroy_child)
end

remote.add_interface("things-ca-v1", api)
