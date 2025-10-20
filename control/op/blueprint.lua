local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local orientation_lib = require("lib.core.orientation.orientation")
local bp_bbox = require("lib.core.blueprint.bbox")
local bp_pos = require("lib.core.blueprint.pos")
local ws_lib = require("lib.core.world-state")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")

local Op = op_lib.Op
local make_world_key = ws_lib.make_world_key
local tostring = tostring
local strformat = string.format
local EMPTY = tlib.EMPTY_STRICT
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local PARENT_TAG = constants.PARENT_TAG
local TAGS_TAG = constants.TAGS_TAG
local table_size = table_size
local Thing = thing_lib.Thing
local pos_close = pos_lib.pos_close
local OP_OVERLAP = op_lib.OpType.OVERLAP
local OP_MFD = op_lib.OpType.MFD
local OP_DESTROY = op_lib.OpType.DESTROY
local deep_copy = tlib.deep_copy

local lib = {}

---@class things.InternalBlueprintEntityInfo
---@field bp_entity BlueprintEntity
---@field bp_index int
---@field bplid int Blueprint local ID
---@field thing_name string Thing registration name.
---@field world_key Core.WorldKey
---@field flid string Frame-local ID
---@field pos MapPosition
---@field thing_id? uint64 ID of the Thing matching this entity, if any.
---@field overlapped_entity? LuaEntity If this BP entity overlapped a real entity when placed, that entity.
---@field overlapped_orientation? Core.Orientation Orientation of the overlapped entity at pre_build.

---@class things.InternalBlueprintGraphEdgeInfo
---@field first int Edge of first/outvertex (bplid)
---@field second int Edge of second/invertex (bplid)
---@field name string Name of the graph this edge belongs to.
---@field data? Tags Optional user data associated with this edge.
---@field resolved true? Whether this edge has been resolved to Things yet.

---@class things.InternalBlueprintParentInfo
---@field parent_bplid int Blueprint local ID of the parent.
---@field child_key string|integer Intended child key in parent
---@field relative_offset? MapPosition Offset from parent to child in parent space.
---@field relative_orientation? Core.Dihedral Relative orientation from parent to child.
---@field resolved true? Whether this parent relationship has been resolved to Things yet.

--------------------------------------------------------------------------------
-- BLUEPRINT INITIALIZATION
--------------------------------------------------------------------------------

---@class things.BlueprintOp: things.Op
---@field public local_id uint A local ID for this operation, unique within the frame.
---@field public surface LuaSurface The surface the blueprint is being built on.
---@field public by_index table<uint, things.InternalBlueprintEntityInfo> Mapping from blueprint entity index to internal info about that entity.
---@field public by_flid table<string, things.InternalBlueprintEntityInfo> Mapping from framelocal ID to internal info about that entity.
---@field public by_bplid table<int, things.InternalBlueprintEntityInfo> Mapping from blueprint local ID to internal info about that entity.
---@field public by_world_key table<Core.WorldKey, things.InternalBlueprintEntityInfo> Mapping from world key to internal info about that entity.
---@field public transform Core.Dihedral The dihedral transformation applied to the blueprint.
---@field public bbox BoundingBox The bounding box of world space in which the blueprint will be built.
---@field public edges {[int]: {[things.InternalBlueprintGraphEdgeInfo]: true}} Edges concerning the given node, index by bplid.
---@field public parents {[int]: things.InternalBlueprintParentInfo} Parent info concerning the given node, index by bplid.
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
	obj.transform = orientation_lib.get_blueprint_transform(ev)

	obj:init_generate_local_ids(frame)
	obj:init_catalogue_positions(frame, bp, surface, ev, entities)
	obj:init_catalogue_overlaps()
	obj:init_catalogue_graph_edges()
	obj:init_catalogue_parents()

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

---Catalogue overlapped entities by this BP
function BlueprintOp:init_catalogue_overlaps()
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
				"BlueprintOp:init_catalogue_overlaps: multiple overlapped entities found for blueprint entity",
				info.bp_entity,
				"at position",
				pos,
				overlapped
			)
		end

		overlapped = overlapped[1]
		if overlapped then
			-- Store overlapped entity.
			info.overlapped_entity = overlapped
			-- Store original orientation of overlapped entity.
			local thing = thing_lib.get_by_unit_number(overlapped.unit_number)
			if thing then
				info.overlapped_orientation = thing:get_orientation()
			else
				info.overlapped_orientation =
					orientation_lib.extract_orientation(overlapped)
			end
		end
	end
end

---Catalogue graph edges declared in blueprint entity tags.
---These must be resolved to real Things later, at the end of the build frame.
function BlueprintOp:init_catalogue_graph_edges()
	local bp_edges = {}
	self.edges = bp_edges
	local n_edges = 0
	for local_id, info in pairs(self.by_bplid) do
		local bp_entity = info.bp_entity
		local edge_tags = (bp_entity.tags or EMPTY)[GRAPH_EDGES_TAG] --[[@as table?]]
		if edge_tags then
			for graph_name, edges in pairs(edge_tags) do
				for to_local_id, edge_data in pairs(edges) do
					to_local_id = tonumber(to_local_id)
					if not to_local_id then
						debug_crash(
							"init_catalogue_graph_edges: invalid @e tag in blueprint",
							info,
							graph_name
						)
					end
					n_edges = n_edges + 1
					---@cast to_local_id integer
					---@type things.InternalBlueprintGraphEdgeInfo
					local edge
					if edge_data == true then
						edge = { first = local_id, second = to_local_id, name = graph_name }
					else
						edge = {
							first = local_id,
							second = to_local_id,
							data = edge_data,
							name = graph_name,
						}
					end
					bp_edges[local_id] = bp_edges[local_id] or {}
					bp_edges[local_id][edge] = true
					bp_edges[to_local_id] = bp_edges[to_local_id] or {}
					bp_edges[to_local_id][edge] = true
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
function BlueprintOp:init_catalogue_parents()
	local parents = {}
	self.parents = parents
	for local_id, info in pairs(self.by_bplid) do
		local bp_entity = info.bp_entity
		local parent_tag = (bp_entity.tags or EMPTY)[PARENT_TAG] --[[@as [string|int, int]?]]
		if parent_tag then
			-- Find parent reference
			local parent_local_id = parent_tag[2]
			local parent_info = self.by_bplid[parent_local_id]
			if not parent_info then
				debug_crash(
					"Application:new: invalid parent tag in blueprint",
					bp_entity,
					parent_tag
				)
			end

			---@type things.InternalBlueprintParentInfo
			local parent_info_rec = {
				parent_bplid = parent_local_id,
				child_key = parent_tag[1],
				relative_offset = parent_tag[3],
				relative_orientation = parent_tag[4],
			}
			parents[local_id] = parent_info_rec
		end
	end
	strace.debug(
		"BlueprintOp:init_catalogue_parents: catalogued",
		table_size(parents),
		"parent-child relationships"
	)
end

--------------------------------------------------------------------------------
-- BLUEPRINT RESOLUTION
-- At the end of the build frame, generate Ops for everything found in the
-- blueprint.
--------------------------------------------------------------------------------

---Examine unresolved construction ops in the given frame. For those that
---correspond to Things that may have been built by this BP, thingify them
---and record resolution info.
---@param frame things.Frame The current frame.
function BlueprintOp:resolve_create_ops(frame)
	local crops = frame.op_set.by_type[op_lib.OpType.CREATE] or EMPTY
	for i = 1, #crops do
		local op = crops[i] --[[@as things.CreateOp]]
		if not op.thing_id then
			local info = self.by_world_key[op.key or ""]
			if info then
				-- This op corresponds to a Thing built from our blueprint.
				-- Thingify it.
				local entity = op.entity
				if entity and entity.valid then
					local thing = Thing:new(info.thing_name)
					thing:set_entity(entity, op.key)
					thing.is_silent = true
					info.thing_id = thing.id
					op.thing_id = thing.id
					op.needs_init = true
					strace.debug(
						"BlueprintOp:resolve_create_ops: CreateOp",
						op,
						"was thingified to",
						thing.id
					)
				else
					strace.warn(
						"BlueprintOp:resolve_create_ops: expected valid entity for CreateOp. Possible early revival or editor pause bug.",
						op
					)
				end
			end
		end
	end
end

---Examine overlapped entities by this BP, filtering out those that are
---MFD or no longer valid.
---This should run in reverse player_index order AFTER create ops are resolved.
---@param frame things.Frame The current frame.
function BlueprintOp:resolve_overlaps(frame)
	local surface = self.surface
	for _, info in pairs(self.by_index) do
		-- Check if catalogued overlap still makes sense.
		local overlapped = info.overlapped_entity
		if
			not overlapped
			or not overlapped.valid
			or (overlapped.status == defines.entity_status.marked_for_deconstruction)
		then
			goto continue
		end

		-- Check if we have a Thing (created ops must resolve first)
		local overlapped_thing =
			thing_lib.get_by_unit_number(overlapped.unit_number)
		if not overlapped_thing then goto continue end

		-- Early-out if there is already an overlap op from an earlier-processed
		-- blueprint op, or some weirdness that would prevent an overlap here.
		local existing_ops = frame.op_set.by_key[info.world_key] or EMPTY
		for i = 1, #existing_ops do
			local op = existing_ops[i]
			local op_type = op.type
			if op_type == OP_OVERLAP then goto continue end
		end

		-- Generate overlap op
		frame:add_op(op_lib.Op:new(OP_OVERLAP, info.world_key))

		-- Overlapping tag updates
		local tags = info.bp_entity.tags
		if tags and tags[TAGS_TAG] then
			frame:add_op(
				op_lib.TagsOp:new(
					overlapped_thing.id,
					info.world_key,
					deep_copy(tags[TAGS_TAG] --[[@as Tags]], true),
					deep_copy(overlapped_thing.tags, true)
				)
			)
		end

		-- Overlapping orientation updates
		-- TODO: implement
		::continue::
	end
end

return lib
