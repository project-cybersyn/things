local event = require("lib.core.event")
local raise = require("control.events.typed").raise

---@param dir_from defines.direction
---@param dir_to defines.direction
local function is_rotation_ccw(dir_from, dir_to)
	local cw_dir = math.abs((dir_to - dir_from) % 16)
	local ccw_dir = math.abs((dir_from - dir_to) % 16)
	return ccw_dir < cw_dir
end

event.bind(
	defines.events.on_player_rotated_entity,
	---@param ev EventData.on_player_rotated_entity
	function(ev)
		local player = game.get_player(ev.player_index)
		local entity = ev.entity
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then return end
		local old_orientation = thing.virtual_orientation
		if old_orientation then
			-- Determine if rotation was clockwise or counterclockwise.
			local ccw = is_rotation_ccw(ev.previous_direction, ev.entity.direction)
			thing:virtual_rotate(ccw)
			raise("thing_virtual_orientation_changed", thing, old_orientation)
		end
	end
)

event.bind(
	defines.events.on_player_flipped_entity,
	---@param ev EventData.on_player_flipped_entity
	function(ev)
		local player = game.get_player(ev.player_index)
		local entity = ev.entity
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then return end
		local old_orientation = thing.virtual_orientation
		if old_orientation then
			thing:virtual_flip(ev.horizontal)
			raise("thing_virtual_orientation_changed", thing, old_orientation)
		end
	end
)
