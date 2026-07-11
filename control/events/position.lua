local events = require("lib.core.event")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")

local get_by_unit_number = thing_lib.get_by_unit_number
local pos_new = pos_lib.pos_new
local pos_add = pos_lib.pos_add

events.bind(
	defines.events.script_raised_teleported,
	---@param ev EventData.script_raised_teleported
	function(ev)
		local un = ev.entity.unit_number

		-- Disentangle thing vs unthing
		local thing = get_by_unit_number(un)
		local root_thing
		local is_different_root = true
		if thing then
			root_thing = thing:get_root()
			is_different_root = root_thing.id ~= thing.id
		else
			local unthing = get_unthing_child(un)
			if not unthing then return end
			thing = get_by_unit_number(unthing[1])
			if thing then
				root_thing = thing:get_root()
			else
				return
			end
		end

		local new_pos = ev.entity.position
		if is_different_root then
			-- Make sure the offset is preserved in the new frame of reference
			local root_entity = root_thing:get_entity()
			if not root_entity then return end
			local offset = pos_new(ev.old_position)
			pos_add(offset, -1, root_entity.position)
			local new_root_pos = pos_new(new_pos)
			pos_add(new_root_pos, -1, offset)

			root_thing:teleport(new_root_pos)
		else
			root_thing:was_teleported(ev.old_position)
		end
	end
)
