-- Internal remote interface.
-- These methods are intended to be called by the Client and are considered undocumented.
-- There are no stability guarantees for these methods, and they may change or be removed at any time.

local api = {}

---@param thing_id things.Id?
function api.get(thing_id)
	local thing = storage.things[thing_id or 0]
	if not thing then return nil end
	return thing:summarize_short()
end

---@param trigger_id things.Id?
---@param trigger_info things.TriggerInfo?
function api.set_trigger_info(trigger_id, trigger_info)
	if not trigger_id then return end
	if not trigger_info then
		storage.trigger_entities[trigger_id] = nil
	else
		storage.trigger_entities[trigger_id] = trigger_info
	end
end

local UINT32_MAX = 4294967295

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
		entity.timeout = 0
	else
		entity.timeout = UINT32_MAX
	end
	return true
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
