local events = require("lib.core.event")
local thing_lib = require("control.thing")
local frame_lib = require("control.frame")
local strace = require("lib.core.strace")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local ws_lib = require("lib.core.world-state")
local op_lib = require("control.op.op")
local orientation_lib = require("lib.core.orientation.orientation")
local oc_lib = require("lib.core.orientation.orientation-class")
local ep_lib = require("lib.core.entity-prototypes")

local PasteSettingsOp = require("control.op.paste-settings").PasteSettingsOp
local ImposeTagsOp = require("control.op.impose-tags").ImposeTagsOp
local ImposeVirtualOrientationOp =
	require("control.op.impose-virtual-orientation").ImposeVirtualOrientationOp
local ImposeNonvirtualOrientationOp = require(
	"control.op.impose-nonvirtual-orientation"
).ImposeNonvirtualOrientationOp

local EMPTY = tlib.EMPTY
local TAGS_TAG = constants.TAGS_TAG
local ORIENTATION_TAG = constants.ORIENTATION_TAG

local o_loose_eq = orientation_lib.loose_eq
local o_stringify = orientation_lib.stringify
local prototype_name_uses_mirroring = ep_lib.prototype_name_uses_mirroring

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

events.bind(
	defines.events.on_blueprint_settings_pasted,
	---@param ev EventData.on_blueprint_settings_pasted
	function(ev)
		local overlapped_entity = ev.entity
		local overlapped_thing =
			thing_lib.get_by_unit_number(overlapped_entity.unit_number)
		strace.trace(
			"Entity",
			overlapped_entity.unit_number,
			"overlapped Thing",
			overlapped_thing and overlapped_thing.id or "nil"
		)
		if not overlapped_thing then return end

		local frame = frame_lib.get_frame()
		local world_key = ws_lib.get_world_key(overlapped_entity)
		frame:mark_resolved(world_key, overlapped_thing)

		-- Imposition of tags
		local is_ghost = (overlapped_entity.type == "entity-ghost")
		local base_new_tags = (
			(is_ghost and overlapped_entity.tags or ev.tags) or EMPTY
		) --[[@as Tags]]
		local imposed_tags = base_new_tags[TAGS_TAG] --[[@as Tags?]]
		local overlapped_tags = overlapped_thing.tags

		if imposed_tags or overlapped_tags then
			frame:add_op(
				ImposeTagsOp:new(
					ev.player_index,
					overlapped_entity,
					world_key,
					overlapped_thing.id,
					overlapped_tags,
					imposed_tags
				)
			)
		end

		if overlapped_thing.virtual_orientation then
			-- Possible imposition of virtual orientation
			-- We must calculate the intended virtual orientation from the orientation stored in the thing tags and the BP placement orientation.
			local bp_op = frame.op_set:findt_unique(
				op_lib.OpType.BLUEPRINT,
				function() return true end
			) --[[@as things.BlueprintOp?]]
			if not bp_op then
				error(
					"LOGIC ERROR: Blueprint settings paste event without a corresponding BlueprintOp in the same frame."
				)
				return
			end
			local blueprinted_orientation = base_new_tags[ORIENTATION_TAG] --[[@as Core.Orientation?]]
			if blueprinted_orientation then
				local transform_index = bp_op.transform_index
				local intended_orientation = orientation_lib.apply_blueprint(
					blueprinted_orientation,
					transform_index
				)
				if
					not o_loose_eq(
						intended_orientation,
						overlapped_thing.virtual_orientation
					)
				then
					strace.debug(
						"on_blueprint_settings_pasted: virtual orientation of Thing",
						overlapped_thing.id,
						"was",
						function() return o_stringify(overlapped_thing.virtual_orientation) end,
						"but intended orientation from blueprint was",
						function() return o_stringify(intended_orientation) end,
						"; adding ImposeOrientationOp"
					)
					local world_key = ws_lib.get_world_key(overlapped_entity)
					frame:add_op(
						ImposeVirtualOrientationOp:new(
							ev.player_index,
							overlapped_entity,
							world_key,
							overlapped_thing.id,
							overlapped_thing.virtual_orientation,
							intended_orientation
						)
					)
				end
			else
				-- TODO: virtually oriented thing has no orientation tag; what do? probs nothing
				strace.warn(
					"on_blueprint_settings_pasted: virtually oriented Thing",
					overlapped_thing.id,
					"was overlapped by an entity with no orientation tag; skipping virtual orientation calcs."
				)
			end
		else
			-- Imposition of nonvirtual orientation
			if ev.previous_direction or ev.mirrored then
				-- Get current orientation
				local current_orientation = orientation_lib.extract(overlapped_entity)
				if not current_orientation then
					strace.warn(
						"on_blueprint_settings_pasted: nonvirtually oriented Thing",
						overlapped_thing.id,
						"was overlapped, but couldn't calculate its new orientation."
					)
					return
				end

				-- Get previous orientation
				local oc = orientation_lib.get_class(current_orientation)
				local oc_props = oc_lib.get_class_properties(oc)
				local previous_direction = ev.previous_direction
					or overlapped_entity.direction
				local previous_mirroring = nil
				if ev.mirrored and oc_props.can_mirror then
					if overlapped_entity.mirroring then
						previous_mirroring = false
					else
						previous_mirroring = true
					end
				end
				local previous_orientation =
					orientation_lib.from_cdm(oc, previous_direction, previous_mirroring)

				frame:add_op(
					ImposeNonvirtualOrientationOp:new(
						ev.player_index,
						overlapped_entity,
						ws_lib.get_world_key(overlapped_entity),
						overlapped_thing.id,
						previous_orientation,
						current_orientation
					)
				)
			end
		end
	end
)
