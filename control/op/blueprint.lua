local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local orientation_lib = require("lib.core.orientation.orientation")
local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")
local CreateEdgeOp = require("control.op.edge").CreateEdgeOp
local ParentOp = require("control.op.parent").ParentOp
local registration_lib = require("control.registration")
local frame_lib = require("control.frame")

local Op = op_lib.Op
local EMPTY = tlib.EMPTY_STRICT
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG
local PARENT_TAG = constants.PARENT_TAG
local ORIENTATION_TAG = constants.ORIENTATION_TAG
local o_stringify = orientation_lib.stringify
local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local NAME_TAG = constants.NAME_TAG
local get_thing_registration = registration_lib.get_thing_registration

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
---@field public by_bplid table<int, things.InternalBlueprintEntityInfo> Mapping from blueprint local ID to internal info about that entity.
---@field public transform_index 0|1|2|3|4|5|6|7 D8 element index representing the blueprint's overall transform.
---@field public build_mode defines.build_mode The build mode in which the blueprint is being built.
local BlueprintOp = class("things.BlueprintOp", Op)
lib.BlueprintOp = BlueprintOp

---@param frame things.Frame The current frame.
---@param orientation_data Core.BlueprintOrientationData The orientation data for the blueprint.
---@param build_mode defines.build_mode The build mode in which the blueprint is being built.
---@param player LuaPlayer? The player who is building the blueprint.
---@param bp Core.Blueprintish The blueprint being built.
---@param surface LuaSurface The surface the blueprint is being built on.
---@param entities BlueprintEntity[] The entities in the blueprint.
---@param by_index table<uint, things.InternalBlueprintEntityInfo> Index info collected at construction phase.
function BlueprintOp:new(
	frame,
	orientation_data,
	build_mode,
	player,
	bp,
	surface,
	entities,
	by_index
)
	local obj = Op.new(self, op_lib.OpType.BLUEPRINT) --[[@as things.BlueprintOp]]
	obj.local_id = frame:generate_id()
	obj.surface = surface
	obj.player_index = player and player.index
	obj.by_index = by_index
	obj.build_mode = build_mode
	obj.transform_index =
		orientation_lib.get_blueprint_transform_index(orientation_data)

	obj:init_generate_local_ids(frame)
	obj:init_catalogue_orientations()

	return obj
end

---Generate IDs local to both the frame and the blueprint.
---@param frame things.Frame The current frame.
function BlueprintOp:init_generate_local_ids(frame)
	-- Generate local ID index
	local by_bplid = {}
	for _, info in pairs(self.by_index) do
		by_bplid[info.bplid] = info
	end
	self.by_bplid = by_bplid
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
-- API HELPERS
--------------------------------------------------------------------------------

---Generate a blueprint prebuild op from the given data if possible.
---@param bp Core.Blueprintish
---@param player LuaPlayer? The player for whom the blueprint is being built. Can be nil if the blueprint is being built by script.
---@param surface LuaSurface
---@param orientation_data Core.BlueprintOrientationData
---@param build_mode defines.build_mode
---@return boolean generated_op True if an op was generated, false if not (e.g. because there were no Things in the blueprint and `calc_unthing_blueprints` is false).
function lib.maybe_generate_blueprint_op(
	bp,
	player,
	surface,
	orientation_data,
	build_mode
)
	local entities = bp.get_blueprint_entities()
	if (not entities) or (#entities == 0) then return false end

	-- Check for Things
	---@type table<uint, things.InternalBlueprintEntityInfo>
	local by_index
	for i, bp_entity in pairs(entities) do
		local tags = bp_entity.tags
		if not tags then goto continue end
		local bplid = tags[LOCAL_ID_TAG]
		if bplid then
			local thing_name = tags[NAME_TAG] --[[@as string?]]
			if not thing_name then thing_name = bp_entity.name end
			local registration = get_thing_registration(thing_name)
			if registration then
				local info = {
					bp_entity = bp_entity,
					bp_index = i,
					bplid = bplid,
					thing_name = thing_name,
				}
				by_index = by_index or {}
				by_index[i] = info
			else
				strace.debug(
					"maybe_generate_blueprint_op: entity",
					bp_entity,
					"has unregistered thing name",
					thing_name,
					"ignoring."
				)
			end
		end
		::continue::
	end

	-- Early out if no Things
	if not by_index then
		strace.debug("maybe_generate_blueprint_op: no Things found in blueprint")
		return false
	end
	by_index = by_index or {}

	-- Generate frame and op
	local frame = frame_lib.get_frame()
	local op = BlueprintOp:new(
		frame,
		orientation_data,
		build_mode,
		player,
		bp,
		surface,
		entities,
		by_index
	)
	frame:add_op(op)
	return true
end

return lib
