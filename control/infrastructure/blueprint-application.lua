-- Code for blueprint application.

local class = require("lib.core.class").class
local mo_lib = require("control.infrastructure.mass-operation")
local world_state = require("lib.core.world-state")
local bp_bbox = require("lib.core.blueprint.bbox")
local bp_pos = require("lib.core.blueprint.pos")
local tlib = require("lib.core.table")
local event = require("lib.core.event")
local constants = require("control.constants")

local LOCAL_ID_TAG = constants.LOCAL_ID_TAG
local TAGS_TAG = constants.TAGS_TAG
local CHILDREN_TAG = constants.CHILDREN_TAG
local PARENT_TAG = constants.PARENT_TAG
local GRAPH_EDGES_TAG = constants.GRAPH_EDGES_TAG

local raise = require("control.events.typed").raise

local make_world_key = world_state.make_world_key
local get_world_key = world_state.get_world_key

local EMPTY = tlib.EMPTY_STRICT

local lib = {}

---Information about Things in a blueprint application.
---@class things.ApplicationThingInfo
---@field public bp_entity BlueprintEntity The blueprint entity.
---@field public bp_index uint The index of the entity in the blueprint's entity list.
---@field public local_id int The @i id in the blueprint.
---@field public world_key Core.WorldKey The world key for the entity.
---@field public thing things.Thing? The Thing that was created or overlapped.
---@field public pos MapPosition? The position of the entity.
---@field public overlapped_entity LuaEntity? The pre-existing entity that was overlapped, if any.
---@field public overlapped_thing things.Thing? The pre-existing Thing that was overlapped, if any.
---@field public built LuaEntity? The actual entity or ghost that was built, if any.
---@field public local_parent? [string|int, int] The parent local id and key in parent, if any.
---@field public local_children? {[string|int]: int} Map of child keys to child local ids, if any.

---@class (exact) things.Application: things.MassOperation
---@field public bp Core.Blueprintish The blueprint being applied.
---@field public surface LuaSurface The surface the blueprint is being applied to.
---@field public by_bp_index {[uint]: things.ApplicationThingInfo} Map of blueprint index to information about the Thing there.
---@field public by_world_key {[Core.WorldKey]: things.ApplicationThingInfo} Map of world key to information about the Thing there.
---@field public by_local_id {[int]: things.ApplicationThingInfo} Map of @i id in the blueprint to information about the Thing there.
---@field public by_thing_id {[int]: things.ApplicationThingInfo} Map of Thing ID to corresponding application info
---@field public things_created {[things.Thing]: true} Set of Things created as part of this application.
---@field public things_overlapped {[things.Thing]: true} Set of Things that were overlapped as part of this application.
---@field public unresolved_edge_set {[things.NamedGraphEdge]: true} Set of local graph edges that could not be resolved because one or both Things were not known yet.
---@field public node_set {[int]: true} Set of local_ids that are connected to edges.
local Application = class("things.Application", mo_lib.MassOperation)
_G.Application = Application
lib.Application = Application

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

---@param player LuaPlayer
---@param bp Core.Blueprintish
---@param surface LuaSurface
---@param ev EventData.on_pre_build
---@return things.Application? application Returns the Application manager object if Things were present, or nil if no Things were in the blueprint.
function Application:new(player, bp, surface, ev)
	-- Find out if there are any Things in the blueprint. Do this before
	-- allocating and doing any intense computations.
	local entities = bp.get_blueprint_entities()
	if (not entities) or (#entities == 0) then
		debug_log("Application:new(): no entities in blueprint")
		return nil
	end

	-- Filter for Things.
	local by_bp_index = {}
	local by_local_id = {}
	for i, bp_entity in pairs(entities) do
		local local_id = (bp_entity.tags or EMPTY)[LOCAL_ID_TAG]
		if local_id then
			local info = {
				bp_entity = bp_entity,
				bp_index = i,
				local_id = local_id,
			}
			---@cast local_id int
			by_bp_index[i] = info
			by_local_id[local_id] = info
		end
	end

	if not next(by_bp_index) then
		debug_log("Application:new(): no Things in blueprint")
		return nil
	end

	-- Generate the MassOperation record.
	local obj = mo_lib.MassOperation.new(self, "application") --[[@as things.Application]]
	obj.player_index = player.index
	obj.bp = bp
	obj.surface = surface
	obj.by_bp_index = by_bp_index
	obj.by_local_id = by_local_id
	obj.by_thing_id = {}
	obj.things_created = {}
	obj.things_overlapped = {}

	-- Now we perform the expensive and complex initialization operations.
	obj:init_catalogue_positions(ev, entities)
	obj:init_catalogue_parent_child()
	obj:init_catalogue_graph_edges()
	obj:init_catalogue_overlaps()

	-- Trigger subtick event. This is basically a virtual "on_blueprint_finished_building" event.
	obj:trigger_subtick_event()

	debug_log("Application:new: created application", obj)
	return obj
end

---Resolve positions and worldkeys of Things within the blueprint.
---@param orientation Core.BlueprintOrientationData Data from the prebuild event indicating how the bp is oriented in the world.
---@param entities BlueprintEntity[] The blueprint entities.
---@return boolean things_present True if there were any Things in the blueprint.
function Application:init_catalogue_positions(orientation, entities)
	local bp = self.bp
	local surface = self.surface

	-- Use bplib to compute full blueprint positioning data.
	local snap = bp.blueprint_snap_to_grid
	local snap_offset = bp.blueprint_position_relative_to_grid
	local snap_absolute = bp.blueprint_absolute_snapping
	local bbox, snap_index = bp_bbox.get_blueprint_bbox(entities)
	local entity_positions = bp_pos.get_blueprint_world_positions(
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

	-- Generate and index by world keys of Things
	local prebuild = get_prebuild_player_state(self.player_index)
	local by_world_key = {}
	for index, info in pairs(self.by_bp_index) do
		local pos = entity_positions[index]
		if not pos then
			debug_crash(
				"BlueprintApplication:init_resolve_things: bplib failed to compute position for entity",
				info.bp_entity
			)
		end
		local bp_entity_name = info.bp_entity.name
		local key = make_world_key(pos, surface.index, bp_entity_name)
		info.world_key = key
		info.pos = pos
		by_world_key[key] = info
		-- Mark key as matching a prebuilt object for use elsewhere.
		prebuild:mark_key_as_prebuilt(key)
	end
	self.by_world_key = by_world_key

	return true
end

---Catalogue blueprint entities that overlap existing Things.
---This should be called after `init_resolve_things`.
function Application:init_catalogue_overlaps()
	for local_id, info in pairs(self.by_local_id) do
		local pos = info.pos
		local bp_entity_name = info.bp_entity.name
		local surface = self.surface
		-- Check for identical overlap
		local overlapped = tlib.filter_in_place(
			surface.find_entities_filtered({
				position = pos,
			}),
			function(e)
				return e.name == bp_entity_name
					or (e.type == "entity-ghost" and e.ghost_name == bp_entity_name)
			end
		)
		overlapped = overlapped[1]
		if overlapped then
			local thing = get_thing_by_unit_number(overlapped.unit_number)
			if thing then
				info.overlapped_thing = thing
				info.overlapped_entity = overlapped
				debug_log(
					"Application:init_catalogue_overlaps: bp_index",
					info.bp_index,
					"overlapped Thing",
					thing.id,
					"with entity",
					(overlapped.valid and overlapped.unit_number) or "<invalid>"
				)
			end
		end
	end
end

---Catalogue graph edges between Things in the blueprint.
---This should be called after `init_resolve_things`.
function Application:init_catalogue_graph_edges()
	self.node_set = {}
	self.unresolved_edge_set = {}
	for local_id, info in pairs(self.by_local_id) do
		local bp_entity = info.bp_entity
		-- Catalogue unresolved edges
		local edge_tags = (bp_entity.tags or EMPTY)[GRAPH_EDGES_TAG] --[[@as table?]]
		if edge_tags then
			for graph_name, edges in pairs(edge_tags) do
				for to_local_id, edge_data in pairs(edges) do
					to_local_id = tonumber(to_local_id)
					if not to_local_id then
						debug_crash(
							"Application:new: invalid @edges tag in blueprint",
							bp_entity,
							graph_name
						)
					end
					---@cast to_local_id integer
					---@type things.NamedGraphEdge
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
					self.node_set[local_id] = true
					self.node_set[to_local_id] = true
					self.unresolved_edge_set[edge] = true
				end
			end
		end
	end
end

---Catalogue parent-child relationships between Things in the blueprint.
---This should be called after `init_resolve_things`.
function Application:init_catalogue_parent_child()
	for local_id, info in pairs(self.by_local_id) do
		local bp_entity = info.bp_entity
		local parent_tag = (bp_entity.tags or EMPTY)[PARENT_TAG] --[[@as [string|int, int]?]]
		if parent_tag then
			-- Find parent reference
			local parent_local_id = parent_tag[2]
			local parent_info = self.by_local_id[parent_local_id]
			if not parent_info then
				debug_crash(
					"Application:new: invalid parent tag in blueprint",
					bp_entity,
					parent_tag
				)
			end

			-- Record parent-child relationship for later resolution
			info.local_parent = parent_tag
			parent_info.local_children = parent_info.local_children or {}
			parent_info.local_children[parent_tag[1]] = local_id
		end
	end
end

--------------------------------------------------------------------------------
-- OPERATION DETECTION
--------------------------------------------------------------------------------

---@param self things.Application
---@param info things.ApplicationThingInfo
---@param operation things.Operation
local function really_include(self, info, operation)
	if not operation.thing then
		local thing = Thing:new_from_operation(operation)
		thing.is_silent = true
		operation.thing = thing
		self.things_created[thing] = true
	end
	self:resolve_local_id(info.local_id, operation.thing, operation.entity)
end

function Application:include(operation, dry_run)
	if operation.player_index ~= self.player_index then return false end
	local world_key = operation.key
	if not world_key then return false end
	local info = self.by_world_key[world_key]
	if not info then return false end
	if info and info.local_id == operation.local_id then
		if not dry_run then really_include(self, info, operation) end
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- RESOLUTION
--------------------------------------------------------------------------------

---Map a local id in the blueprint to a Thing and resolve any outstanding
---relationships that may depend on that local id.
---@param local_id int
---@param thing things.Thing
---@param built? LuaEntity The actual entity or ghost that was built, if any.
function Application:resolve_local_id(local_id, thing, built)
	debug_log(
		"Application:resolve_local_id: mapping local id",
		local_id,
		"to Thing",
		thing.id
	)
	local info = self.by_local_id[local_id]
	if not info then
		debug_crash("Application:resolve_local_id: unknown local id", local_id)
	end
	info.thing = thing
	info.built = built
	self.by_thing_id[thing.id] = info
	self:resolve_graph_edges(local_id)
	self:resolve_parent_child(local_id)
end

function Application:resolve_graph_edges(local_id)
	debug_log(
		"Application:resolve_graph_edges: resolving edges for local id",
		local_id,
		self.node_set,
		self.unresolved_edge_set
	)
	if not self.node_set[local_id] then return end
	local thing = self.by_local_id[local_id].thing
	if not thing then return end
	for edge in pairs(self.unresolved_edge_set) do
		if edge.first ~= local_id and edge.second ~= local_id then goto continue end
		local other_local_id = (edge.first == local_id) and edge.second
			or edge.first
		local other_thing = self.by_local_id[other_local_id].thing
		if other_thing then
			self.unresolved_edge_set[edge] = nil
			thing:graph_connect(edge.name, other_thing, edge.data)
			debug_log(
				"Application:resolve_graph_edges: connected",
				thing.id,
				other_thing.id,
				"on graph",
				edge.name
			)
		end
		::continue::
	end
end

function Application:resolve_parent_child(local_id)
	debug_log(
		"Application:resolve_parent_child: resolving parent-child for local id",
		local_id
	)
	local info = self.by_local_id[local_id]
	local thing = info.thing
	if not thing then return end

	-- Resolve child -> parent
	local key_and_parent_id = info.local_parent
	if key_and_parent_id then
		local child_key, parent_local_id =
			key_and_parent_id[1], key_and_parent_id[2]
		local parent_thing = self.by_local_id[parent_local_id].thing
		if parent_thing then
			local added = parent_thing:add_child(child_key, thing)
			if added then
				debug_log(
					"Application:resolve_parent_child: added child",
					thing.id,
					"to parent",
					parent_thing.id,
					"with key",
					child_key
				)
			end
		end
	end

	-- Resolve parent -> children
	local child_keys = info.local_children
	if child_keys then
		for child_key, child_local_id in pairs(child_keys) do
			local child_thing = self.by_local_id[child_local_id].thing
			if child_thing then
				local added = thing:add_child(child_key, child_thing)
				if added then
					debug_log(
						"Application:resolve_parent_child: added child",
						child_thing.id,
						"to parent",
						thing.id,
						"with key",
						child_key
					)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- LATE PHASE
--------------------------------------------------------------------------------

---For overlaps detected early, invalidate any that don't make sense anymore.
---For example, if the overlapping entity has been removed or marked for
---deconstruction.
function Application:invalidate_bad_overlaps()
	for _, info in pairs(self.by_local_id) do
		local entity = info.overlapped_entity
		if not entity then goto continue end
		if not entity.valid then
			debug_log(
				"Application:invalidate_bad_overlaps: invalidating overlap for local id",
				info.local_id,
				"because entity is invalid"
			)
			info.overlapped_entity = nil
			info.overlapped_thing = nil
		elseif entity.status == defines.entity_status.marked_for_deconstruction then
			debug_log(
				"Application:invalidate_bad_overlaps: invalidating overlap for local id",
				info.local_id,
				"because entity is marked for deconstruction"
			)
			info.overlapped_entity = nil
			info.overlapped_thing = nil
		end
		::continue::
	end
end

---Resolve all local ids in the blueprint that overlapped existing Things.
---This must be called after `invalidate_bad_overlaps`
function Application:resolve_overlapping_local_ids()
	for _, info in pairs(self.by_local_id) do
		if info.overlapped_entity and info.overlapped_thing then
			self:resolve_local_id(info.local_id, info.overlapped_thing, nil)
		end
	end
end

---Apply tags from the blueprint to all overlapped Things.
---Must be called after `invalidate_bad_overlaps`
function Application:apply_overlapping_tags()
	for _, info in pairs(self.by_local_id) do
		if info.overlapped_thing then
			local bp_entity = info.bp_entity
			local new_tags = (bp_entity.tags or EMPTY)[TAGS_TAG]
			if new_tags then
				info.overlapped_thing:set_tags(new_tags --[[@as Tags]])
				debug_log(
					"Application:apply_overlapping_tags: applied tags to Thing",
					info.overlapped_thing.id,
					info.overlapped_thing.tags
				)
			end
		end
	end
end

-- Apply initial ghost/real state to built things, then fire init event.
function Application:initialize_created_things()
	for thing in pairs(self.things_created) do
		thing:apply_status()
		thing.is_silent = nil
	end
	for thing in pairs(self.things_created) do
		thing:initialize()
	end
end

function Application:on_subtick()
	debug_log("Application:on_subtick: finishing application")
	self:invalidate_bad_overlaps()
	self:resolve_overlapping_local_ids()
	self:apply_overlapping_tags()
	self:initialize_created_things()

	self:destroy()
end

return lib
