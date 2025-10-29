local events = require("lib.core.event")
local thing_lib = require("control.thing")
local frame_lib = require("control.frame")
local strace = require("lib.core.strace")

local PasteSettingsOp = require("control.op.paste-settings").PasteSettingsOp

events.bind(
	defines.events.on_entity_settings_pasted,
	---@param ev EventData.on_entity_settings_pasted
	function(ev)
		local source_entity = ev.source
		local target_entity = ev.destination

		local source_thing = thing_lib.get_by_unit_number(source_entity.unit_number)
		local target_thing = thing_lib.get_by_unit_number(target_entity.unit_number)

		if not source_thing or not target_thing then return end

		if source_thing.name ~= target_thing.name then
			strace.debug(
				"paste-settings event: source and target Things have different names; skipping"
			)
			return
		end

		local frame = frame_lib.get_frame()
		local op = PasteSettingsOp:new(
			ev.player_index,
			target_thing.id,
			target_thing.tags,
			source_thing.tags
		)
		frame:add_op(op)
	end
)
