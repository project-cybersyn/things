-- Factorio rot and flip event handlers.

local events = require("lib.core.event")
local frame_lib = require("control.frame")
local orientation_lib = require("lib.core.orientation.orientation")
local oclass_lib = require("lib.core.orientation.orientation-class")
local dih_lib = require("lib.core.math.dihedral")
local strace = require("lib.core.strace")
local OrientationOp = require("control.op.orientation").OrientationOp

local WORLD = oclass_lib.OrientationContext.World
local Rinv = orientation_lib.Rinv
local floor = math.floor

events.bind(
	defines.events.on_player_rotated_entity,
	---@param ev EventData.on_player_rotated_entity
	function(ev)
		local player = game.get_player(ev.player_index)
		local entity = ev.entity
		local thing = get_thing_by_unit_number(entity.unit_number)
		local prev_dir = ev.previous_direction
		local curr_dir = ev.entity.direction
		if not thing then return end
		if prev_dir == curr_dir then
			strace.debug(
				"on_player_rotated_entity: Previous direction equals current direction; no rotation occurred"
			)
			return
		end

		-- Find relation between previous and current direction.
		-- TODO: use real order of dihedral group; offload this to orientation_lib
		local diff = (floor(curr_dir / 4) - floor(prev_dir / 4)) % 4
		local R = dih_lib.encode(4, diff, 0)

		-- Need to generate an OrientationOp.
		local frame = frame_lib.get_frame()

		local old_orientation = thing.virtual_orientation
		if old_orientation then
			frame:add_op(
				OrientationOp:new(ev.player_index, entity, thing.id, old_orientation, R)
			)
		else
			-- World orientation case; thing should already be reoriented.
			local current_orientation = thing:get_orientation()
			if not current_orientation then
				debug_crash("on_player_rotated_entity: Thing has no orientation")
				return
			end
			local unrotation = dih_lib.invert(R)
			frame:add_op(
				OrientationOp:new(
					ev.player_index,
					entity,
					thing.id,
					nil,
					nil,
					current_orientation,
					unrotation
				)
			)
		end
	end
)

events.bind(
	defines.events.on_player_flipped_entity,
	---@param ev EventData.on_player_flipped_entity
	function(ev)
		local player = game.get_player(ev.player_index)
		local entity = ev.entity
		local thing = get_thing_by_unit_number(entity.unit_number)
		if not thing then return end

		-- Need to generate an OrientationOp.
		local frame = frame_lib.get_frame()

		local old_orientation = thing.virtual_orientation
		if old_orientation then
			-- Virtual orientation case; orientation not yet applied.
			local flip = ev.horizontal and orientation_lib.H(old_orientation, WORLD)
				or orientation_lib.V(old_orientation, WORLD)
			if flip then
				frame:add_op(
					OrientationOp:new(
						ev.player_index,
						entity,
						thing.id,
						old_orientation,
						flip
					)
				)
			else
				strace.warn(
					frame.debug_string,
					"on_player_flipped_entity: Could not determine flip dihedral"
				)
			end
		else
			-- World orientation case; thing should already be reoriented.
			local current_orientation = thing:get_orientation()
			if not current_orientation then
				debug_crash("on_player_flipped_entity: Thing has no orientation")
				return
			end
			local unflip = ev.horizontal
					and orientation_lib.H(current_orientation, WORLD)
				or orientation_lib.V(current_orientation, WORLD)
			if unflip then
				unflip = dih_lib.invert(unflip)
				frame:add_op(
					OrientationOp:new(
						ev.player_index,
						entity,
						thing.id,
						nil,
						nil,
						current_orientation,
						unflip
					)
				)
			else
				strace.warn(
					frame.debug_string,
					"on_player_flipped_entity: Could not determine unflip dihedral"
				)
			end
		end
	end
)
