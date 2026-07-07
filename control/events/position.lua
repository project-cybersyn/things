local events = require("lib.core.event")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")

events.bind(
	defines.events.script_raised_teleported,
	---@param ev EventData.script_raised_teleported
	function(ev)
		local thing = thing_lib.get_by_unit_number(ev.entity.unit_number)
		if not thing then return end

		local new_pos = ev.entity.position
		local root_thing = thing:get_root()

		if root_thing.id ~= thing.id then
			-- Make sure the offset is preserved in the new frame of reference
			local root_entity = root_thing:get_entity()
			if not root_entity then return end
			local offset = pos_lib.pos_new(ev.old_position)
			pos_lib.pos_add(offset, -1, root_entity.position)
			local new_root_pos = pos_lib.pos_new(new_pos)
			pos_lib.pos_add(new_root_pos, -1, offset)

			root_thing:teleport(new_root_pos)
		else
			root_thing:was_teleported(ev.old_position)
		end
	end
)
