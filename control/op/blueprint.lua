local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local oclass_lib = require("lib.core.orientation.orientation-class")
local orientation_lib = require("lib.core.orientation.orientation")
local bp_bbox = require("lib.core.blueprint.bbox")
local bp_pos = require("lib.core.blueprint.pos")
local ws_lib = require("lib.core.world-state")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")
local overlap_op_lib = require("control.op.overlap")
local CreateEdgeOp = require("control.op.edge").CreateEdgeOp
local ParentOp = require("control.op.parent").ParentOp

local Op = op_lib.Op
local OverlapOp = overlap_op_lib.OverlapOp
local make_world_key = ws_lib.make_world_key
local tostring = tostring
local strformat = string.format
local EMPTY = tlib.EMPTY_STRICT
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local PARENT_TAG = constants.PARENT_TAG
local TAGS_TAG = constants.TAGS_TAG
local ORIENTATION_TAG = constants.ORIENTATION_TAG
local table_size = table_size
local Thing = thing_lib.Thing
local pos_close = pos_lib.pos_close
local OP_OVERLAP = op_lib.OpType.OVERLAP
local OP_MFD = op_lib.OpType.MFD
local OP_DESTROY = op_lib.OpType.DESTROY
local deep_copy = tlib.deep_copy
local o_stringify = orientation_lib.stringify
local o_loose_eq = orientation_lib.loose_eq
local get_thing_by_id = thing_lib.get_by_id

local lib = {}

---@class things.InternalBlueprintEntityInfo
---@field bp_entity BlueprintEntity
---@field bp_index int
---@field bplid int Blueprint local ID
---@field thing_name string Thing registration name.
---@field world_key Core.WorldKey
---@field flid string Frame-local ID
---@field pos MapPosition
---@field blueprinted_orientation Core.Orientation Orientation of the object within the blueprint itself.
---@field intended_orientation Core.Orientation Intended world orientation of this entity after blueprint placement.
---@field thing_id? uint64 ID of the Thing matching this entity, if any.
---@field overlapped_entity? LuaEntity If this BP entity overlapped a real entity when placed, that entity.
---@field overlapped_orientation? Core.Orientation Orientation of the overlapped entity at pre_build.

--------------------------------------------------------------------------------
-- INIT/BUILD PHASE
--------------------------------------------------------------------------------

---@class things.BlueprintOp: things.Op
---@field public local_id uint A local ID for this operation, unique within the frame.
---@field public surface LuaSurface The surface the blueprint is being built on.
---@field public by_index table<uint, things.InternalBlueprintEntityInfo> Mapping from blueprint entity index to internal info about that entity.
---@field public by_flid table<string, things.InternalBlueprintEntityInfo> Mapping from framelocal ID to internal info about that entity.
---@field public by_bplid table<int, things.InternalBlueprintEntityInfo> Mapping from blueprint local ID to internal info about that entity.
---@field public by_world_key table<Core.WorldKey, things.InternalBlueprintEntityInfo> Mapping from world key to internal info about that entity.
---@field public transform_index 0|1|2|3|4|5|6|7 D8 element index representing the blueprint's overall transform.
---@field public bbox BoundingBox The bounding box of world space in which the blueprint will be built.
---@field public build_mode defines.build_mode The build mode in which the blueprint is being built.
local BlueprintOp = class("things.BlueprintOp", Op)
lib.BlueprintOp = BlueprintOp

---@param frame things.Frame The current frame.
---@param ev EventData.on_pre_build The on_pre_build event data.
---@param player LuaPlayer The player who is building the blueprint.
---@param bp Core.Blueprintish The blueprint being built.
---@param surface LuaSurface The surface the blueprint is being built on.
---@param entities BlueprintEntity[] The entities in the blueprint.
---@param by_index table<uint, things.InternalBlueprintEntityInfo> Index info collected at construction phase.
function BlueprintOp:new(frame, ev, player, bp, surface, entities, by_index)
	local obj = Op.new(self, op_lib.OpType.BLUEPRINT) --[[@as things.BlueprintOp]]
	obj.local_id = frame:generate_id()
	obj.surface = surface
	obj.player_index = player.index
	obj.by_index = by_index
	obj.build_mode = ev.build_mode
	obj.transform_index = orientation_lib.get_blueprint_transform_index(ev)

	obj:init_generate_local_ids(frame)
	obj:init_catalogue_positions(frame, bp, surface, ev, entities)
	obj:init_catalogue_orientations()
	obj:init_catalogue_overlaps(frame)

	return obj
end

---@param bp_local_id string|integer The local ID within the blueprint.
---@return string #The local ID unique within the frame.
function BlueprintOp:to_frame_local_id(bp_local_id)
	return strformat("%d:%s", self.local_id, tostring(bp_local_id))
end

---Generate IDs local to both the frame and the blueprint.
---@param frame things.Frame The current frame.
function BlueprintOp:init_generate_local_ids(frame)
	local op_local_id = self.local_id

	-- Generate local IDs
	for _, info in pairs(self.by_index) do
		info.flid = strformat("%d:%d", op_local_id, info.bplid)
	end

	-- Generate local ID index
	local by_flid, by_bplid = {}, {}
	for _, info in pairs(self.by_index) do
		by_flid[info.flid] = info
		by_bplid[info.bplid] = info
	end
	self.by_flid = by_flid
	self.by_bplid = by_bplid
end

---Use bplib to compute bbox and positions for each entity.
---@param frame things.Frame The current frame.
---@param bp Core.Blueprintish The blueprint being built.
---@param surface LuaSurface The surface the blueprint is being built on.
---@param orientation Core.BlueprintOrientationData Orientation in which the blueprint is being built.
---@param entities BlueprintEntity[] The entities in the blueprint.
function BlueprintOp:init_catalogue_positions(
	frame,
	bp,
	surface,
	orientation,
	entities
)
	-- Use bplib to compute full blueprint positioning data.
	local snap = bp.blueprint_snap_to_grid
	local snap_offset = bp.blueprint_position_relative_to_grid
	local snap_absolute = bp.blueprint_absolute_snapping
	local bbox, snap_index = bp_bbox.get_blueprint_bbox(entities)
	local entity_positions, world_bbox = bp_pos.get_blueprint_world_positions(
		entities,
		nil,
		bbox,
		snap_index,
		orientation.position,
		orientation.direction,
		orientation.flip_horizontal,
		orientation.flip_vertical,
		snap_absolute and snap or nil,
		snap_offset,
		mod_settings.debug and surface or nil
	)
	self.bbox = world_bbox

	-- Generate world key index
	local by_world_key = {}
	for index, info in pairs(self.by_index) do
		local pos = entity_positions[index]
		if not pos then
			debug_crash(
				"BlueprintOp:init_catalogue_positions: bplib failed to compute position for entity",
				info.bp_entity
			)
		end
		local bp_entity_name = info.bp_entity.name
		local key = make_world_key(pos, surface.index, bp_entity_name)
		info.world_key = key
		info.pos = pos
		by_world_key[key] = info
		-- Mark key as matching a prebuilt object
		frame:mark_prebuild(key, self.player_index)
	end
	self.by_world_key = by_world_key
	strace.debug(
		"BlueprintOp:init_catalogue_positions: catalogued",
		table_size(self.by_world_key),
		"worldkeys"
	)
end

---Catalogue intended orientations for things in this BP.
function BlueprintOp:init_catalogue_orientations()
	for idx, info in pairs(self.by_index) do
		local bp_entity = info.bp_entity
		local tags = bp_entity.tags or EMPTY
		local blueprinted_orientation
		if tags and tags[ORIENTATION_TAG] then
			blueprinted_orientation = tags[ORIENTATION_TAG] --[[@as Core.Orientation]]
		else
			blueprinted_orientation = orientation_lib.extract_bp(bp_entity)
		end
		info.blueprinted_orientation = blueprinted_orientation
		-- Apply overall blueprint transform to get intended world orientation.
		local intended_orientation = orientation_lib.apply_blueprint(
			blueprinted_orientation,
			self.transform_index
		)
		info.intended_orientation = intended_orientation
		strace.debug(
			"BlueprintOp:init_catalogue_orientations: bp_entity",
			idx,
			":",
			bp_entity.name,
			"blueprinted",
			function() return o_stringify(blueprinted_orientation) end,
			"intended",
			function() return o_stringify(intended_orientation) end
		)
	end
end

---Catalogue overlapped entities by this BP. We do this during the build
---phase to make sure the `pre_build` information is as fresh as possible.
---@param frame things.Frame The current frame.
function BlueprintOp:init_catalogue_overlaps(frame)
	local surface = self.surface
	for _, info in pairs(self.by_index) do
		-- Check for identical overlap
		local pos = info.pos
		local bp_entity_name = info.bp_entity.name
		local overlapped = tlib.filter_in_place(
			surface.find_entities_filtered({
				position = pos,
			}),
			function(e)
				return e.status ~= defines.entity_status.marked_for_deconstruction
					and (e.name == bp_entity_name or (e.type == "entity-ghost" and e.ghost_name == bp_entity_name))
					and pos_close(e.position, pos)
			end
		)
		if #overlapped > 1 then
			strace.warn(
				"BlueprintOp:init_catalogue_overlaps: multiple identical overlapped entities found for blueprint entity",
				info.bp_entity,
				"at position",
				pos,
				overlapped
			)
		end

		-- Generate Overlap op.
		overlapped = overlapped[1]
		if overlapped then
			local thing = thing_lib.get_by_unit_number(overlapped.unit_number)
			if thing then
				local imposed_tags = nil
				local bp_tags = info.bp_entity.tags
				if bp_tags and bp_tags[TAGS_TAG] then
					imposed_tags = bp_tags[TAGS_TAG] --[[@as Tags]]
				end
				frame:add_op(
					OverlapOp:new(
						self.player_index,
						overlapped,
						bp_entity_name,
						pos,
						info.world_key,
						thing.id,
						thing.tags,
						imposed_tags,
						info.intended_orientation
					)
				)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- CATALOGUE PHASE
--------------------------------------------------------------------------------

---Catalogue graph edges declared in blueprint entity tags.
---@param frame things.Frame The current frame.
function BlueprintOp:catalogue_graph_edges(frame)
	local n_edges = 0
	local by_bplid = self.by_bplid
	for from_local_id, from_info in pairs(by_bplid) do
		local bp_entity = from_info.bp_entity
		local edge_tags = (bp_entity.tags or EMPTY)[GRAPH_EDGES_TAG] --[[@as table?]]
		if edge_tags then
			for graph_name, edges in pairs(edge_tags) do
				for to_local_id, edge_data in pairs(edges) do
					to_local_id = tonumber(to_local_id)
					if not to_local_id then
						debug_crash(
							"init_catalogue_graph_edges: invalid @e tag in blueprint",
							from_info,
							graph_name
						)
					end
					n_edges = n_edges + 1
					---@cast to_local_id integer
					local to_info = by_bplid[to_local_id]
					if to_info then
						if edge_data == true then
							frame:add_op(
								CreateEdgeOp:new(
									self.player_index,
									from_info.world_key,
									to_info.world_key,
									graph_name
								)
							)
						else
							frame:add_op(
								CreateEdgeOp:new(
									self.player_index,
									from_info.world_key,
									to_info.world_key,
									graph_name,
									edge_data
								)
							)
						end
					else
						debug_crash(
							"init_catalogue_graph_edges: invalid @e tag in blueprint, target bplid not found",
							from_info,
							graph_name,
							to_local_id
						)
					end
				end
			end
		end
	end
	strace.debug(
		"BlueprintOp:init_catalogue_graph_edges: catalogued",
		n_edges,
		"graph edges"
	)
end

---Catalogue parent-child relationships declared in blueprint entity tags.
---These must be resolved to real Things later, at the end of the build frame.
function BlueprintOp:catalogue_parents(frame)
	local n_parents = 0
	for child_bplid, child_info in pairs(self.by_bplid) do
		local child_bp_entity = child_info.bp_entity
		local parent_tag = (child_bp_entity.tags or EMPTY)[PARENT_TAG] --[[@as things.ParentRelationshipInfo?]]
		if parent_tag then
			-- Find parent reference
			local parent_local_id = parent_tag[1]
			local parent_info = self.by_bplid[parent_local_id]
			if not parent_info then
				debug_crash(
					"Application:new: invalid parent tag in blueprint",
					child_bp_entity,
					parent_tag
				)
			end

			n_parents = n_parents + 1
			frame:add_op(
				ParentOp:new(
					child_info.world_key,
					parent_info.world_key,
					parent_tag[2],
					parent_tag[3],
					parent_tag[4]
				)
			)
		end
	end
	strace.debug(
		"BlueprintOp:init_catalogue_parents: catalogued",
		n_parents,
		"parent-child relationships"
	)
end

function BlueprintOp:catalogue(frame)
	self:catalogue_graph_edges(frame)
	self:catalogue_parents(frame)
end

--------------------------------------------------------------------------------
-- RESOLVE PHASE
--------------------------------------------------------------------------------

function BlueprintOp:resolve(frame)
	overlap_op_lib.consolidate_overlap_ops(frame.op_set)
end

--------------------------------------------------------------------------------
-- APPLY PHASE
--------------------------------------------------------------------------------

---Examine construction ops in the given frame. For those that
---correspond to Things that may have been built by this BP, resolve
---as needed.
---@param frame things.Frame The current frame.
function BlueprintOp:resolve_create_ops(frame)
	local crops = frame.op_set.by_type[op_lib.OpType.CREATE] or EMPTY
	strace.debug(
		frame.debug_string,
		"BlueprintOp:resolve_create_ops: resolving ",
		#crops,
		" create ops for player ",
		self.player_index
	)
	for i = 1, #crops do
		local op = crops[i] --[[@as things.CreateOp]]
		local info = self.by_world_key[op.key or ""]
		if info and not op.skip then
			-- This op corresponds to a Thing built from our blueprint.
			-- Check if orientation matches intended orientation.
			local thing = get_thing_by_id(op.thing_id)
			if not thing then
				error(
					"BlueprintOp:resolve_create_ops: A resolved create op does not have an extant thing id. This should be impossible. Id: "
						.. tostring(op.thing_id)
				)
			end
			local O = thing:get_orientation()
			local intended_orientation = info.intended_orientation
			if O then
				if not o_loose_eq(O, intended_orientation) then
					strace.warn(
						frame.debug_string,
						"BlueprintOp:resolve_create_ops: Thing ID",
						thing.id,
						"orientation",
						function() return o_stringify(O) end,
						"does not match intended orientation",
						function() return o_stringify(intended_orientation) end,
						"- imposing intended orientation."
					)
					thing:set_orientation(intended_orientation, true)
				else
					strace.trace(
						frame.debug_string,
						"BlueprintOp:resolve_create_ops: Thing ID",
						thing.id,
						"orientation matches intended orientation."
					)
				end
			else
				debug_crash(
					"BlueprintOp:resolve_create_ops: Thing has no orientation; cannot compare to intended orientation.",
					thing
				)
			end
		end
	end
end

function BlueprintOp:apply(frame) self:resolve_create_ops(frame) end

return lib
