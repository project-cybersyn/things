local class = require("lib.core.class").class
local scheduler = require("lib.core.scheduler")
local world_state = require("lib.core.world-state")
local urs_lib = require("lib.core.undo-redo-stack")
local counters = require("lib.core.counters")
local mconst = require("lib.core.math.constants")
local tlib = require("lib.core.table")

local INF = mconst.BIG_INT
local NINF = mconst.BIG_NEG_INT
local RECONCILE_ID_TAG = "@rid"
local THINGS_TAGS = "@tags"

local get_world_key = world_state.get_world_key
local make_world_key = world_state.make_world_key

-- Virtualized undo/redo
--
-- The general idea of this code is that when an undoable action occurs, we
-- need to know which if any Things were involved, and when an undo occurs
-- we need to restore the identities/states of Things appropriately.
--
-- Unfortunately, Factorio's
-- paucity of events and information, along with imo backwards event ordering
-- makes this a massively difficult problem.
--
-- Credit for various ideas in fixing this goes to hgschmie's Fiber Optics
-- mod and Telkine2018's Compact Circuits mod, both of whom contain partial
-- versions of this idea. My goal here was to make a fully general working
-- implementation. All code is newly written.
--
-- The things we need to achieve are:
-- 1) When an entity or ghost is destroyed by an undoable action, tag the action
-- with the Thing id and pickle the Thing for later restoration.
-- 2) When an entity or ghost is built, was it the result of an undo recorded in (1)? If
-- so, restore its Thing-ness; if not, treat as new construction.
--
-- (1) is complicated by the fact that there is no event whatsoever for when
-- an entry is added to the undo stack. In fact if the game is paused there are
-- situations where it is *impossible* for any mod code to run between an
-- undo entry being pushed and that same entry being popped. In such situations
-- the fact that the undo stack supports tags is useless because there is
-- simply no time to tag it.
--
-- This is where some ideas from Fiber Optics and Compact Circuits come in.
-- We create "undo markers" keyed by world keys (position, surface, name).
-- When we get the chance (i.e. before an undoable thing occurs) we opportunistically
-- reconcile these markers with the undo stack, saving them as tags. For those
-- moments where there haven't been any events and we can't rely on tags,
-- we treat outstanding unreconciled markers as if they were potential tags.
--
-- (2) is likewise complicated by screwy event ordering and missing events.
-- This time around, there is no event for when an undo operation begins. You
-- just get a bunch of build events followed by an `on_undo_applied` event.
-- Furthermore, the entry has already been popped from the stack before
-- any of these events.
--
-- Cracking this relies on several ideas.
--
-- First, it turns out that undo-events aren't associated with a `pre_build`.
-- This means by bookkeeping `pre_build` using world keys, we can basically
-- figure out which entities are being built by undo operations and which
-- aren't.
--
-- Second, we once again have to virtualize the stack here because we need
-- a decision on whether a build is an undo during `on_build`. We can't wait
-- for an `on_undo_applied` that may never come. So we maintain a "top set"
-- of world keys that are on the top of either the undo or redo stack, plus
-- all outstanding unreconciled keys. A build is an undo if its world key
-- matches any of those.
--
-- What this all amounts to is we basically have to virtualize a big chunk
-- of the undo system in Lua and perform a bunch of very expensive bookkeeping
-- but it IS just barely possible in userspace to have generally correct undo
-- for custom entities.
--
-- Anyway, rant over, here's the implementation.

---Marker associated with an undoable action affecting a Thing.
---@class (exact) things.UndoMarker: Core.WorldState
---@field public id int Global unique id for this marker
---@field public thing_id uint The Thing id associated with the marker
---@field public retain boolean? Whether the Thing associated with this marker should be retained via refcount.
---@field public marker_type string The type of marker
---@field public data? table Additional data associated with the marker
local UndoMarker = class("things.UndoMarker")
_G.UndoMarker = UndoMarker

---Create an undo marker.
---@param entity LuaEntity A *valid* entity.
---@param thing things.Thing
---@param retain boolean? Whether to retain the Thing via refcount.
---@param marker_type string The type of marker
---@param data? table Additional data associated with the marker
---@return things.UndoMarker
function UndoMarker:new(entity, thing, retain, marker_type, data)
	local state = world_state.get_world_state(entity)
	local obj = setmetatable(state, self)
	---@cast obj things.UndoMarker
	obj.id = counters.next("undo_marker")
	obj.thing_id = thing.id
	obj.retain = retain
	if retain then thing:undo_ref() end
	obj.marker_type = marker_type
	obj.data = data
	return obj
end

---Clone an undo marker. Results in an otherwise identical marker with a new
---id. If the marker retains a Thing, the Thing's refcount is incremented
---again.
---@return things.UndoMarker
function UndoMarker:clone()
	local obj = tlib.assign({}, self)
	setmetatable(obj, getmetatable(self))
	---@cast obj things.UndoMarker
	obj.id = counters.next("undo_marker")
	if obj.retain then
		local thing = get_thing(obj.thing_id)
		if thing then thing:undo_ref() end
	end
	return obj
end

---Destroy an undo marker. If the marker retains a Thing, the Thing's refcount
---is decremented.
function UndoMarker:destroy()
	if self.retain then
		local thing = get_thing(self.thing_id)
		if thing then thing:undo_deref() end
	end
end

---Reconciliation between an item (Set of actions) on the undo/redo stack and
---the set of undo markers.
---@class (exact) things.UndoReconciliation
---@field public id int Global unique id for this reconciliation
---@field public markers {[int]: things.UndoMarker} Markers associated with this reconciliation, by id.
local UndoReconciliation = class("things.UndoReconciliation")
_G.UndoReconciliation = UndoReconciliation

function UndoReconciliation:new()
	local obj = setmetatable({}, self)
	obj.id = counters.next("undo_reconciliation")
	obj.markers = {}
	return obj
end

---@param marker things.UndoMarker
function UndoReconciliation:add_marker(marker) self.markers[marker.id] = marker end

function UndoReconciliation:destroy()
	for _, marker in pairs(self.markers) do
		marker:destroy()
	end
end

---Per player virtualized undo/redo state. One of these must exist in `storage`
---for each active player.
---@class (exact) things.VirtualUndoPlayerState
---@field public player_index uint The player index this state is for.
---@field public unreconciled_markers {[Core.WorldKey]: things.UndoMarker} Map from world keys to possible markers caused by this player since last reconcile.
---@field public reconciliations {[int]: things.UndoReconciliation} Reconciliations on the stack, by id.
---@field public top_marker_set {[Core.WorldKey]: things.UndoMarker} Set of world keys at the top of either undo or redo stack as of last reconcile.
---@field public last_reconcile_ticks_played uint The unpaused `ticks_played` value when the last reconcile was performed.
local VirtualUndoPlayerState = class("things.VirtualUndoPlayerState")
_G.VirtualUndoPlayerState = VirtualUndoPlayerState

---@param player_index int
function VirtualUndoPlayerState:new(player_index)
	local obj = setmetatable({}, self)
	obj.player_index = player_index
	obj.unreconciled_markers = {}
	obj.reconciliations = {}
	obj.top_marker_set = {}
	obj.last_reconcile_ticks_played = 0
	return obj
end

---Determine if the top item on either undo or redo stack has a marker for the given key.
---@param key Core.WorldKey
---@return things.UndoMarker? marker The marker, if any.
function VirtualUndoPlayerState:get_top_marker(key)
	return self.top_marker_set[key] or self.unreconciled_markers[key]
end

---Add an unreconciled marker to this undo state.
---@param marker things.UndoMarker
function VirtualUndoPlayerState:add_marker(marker)
	local key = marker.key
	-- Already exists
	if self.unreconciled_markers[key] then return end
	self.unreconciled_markers[key] = marker
end

---Reconcile if needed based on the paused tick
function VirtualUndoPlayerState:reconcile_if_needed()
	if (self.last_reconcile_ticks_played or 0) < game.ticks_played then
		self:perform_reconcile()
	end
end

---@param action UndoRedoAction
---@param key string
---@param marker things.UndoMarker
---@return Tags? tags Tags to add to the action, or nil if none.
local function reconcile_action(action, key, marker)
	if
		action.type == "removed-entity" and marker.marker_type == "deconstruction"
	then
		-- Match deconstruction marker to removed-entity action
		debug_log(
			"perform_reconcile: matched deconstruction marker to action",
			key,
			marker
		)
		return { ["destroyed"] = marker.thing_id }
	end
	return nil
end

---@param vups things.VirtualUndoPlayerState
---@param view Core.UndoRedoStackView
---@return boolean changed Whether any new reconciliations were needed.
---@return int bottom_id Rec.ID at the bottom of the stack.
local function reconcile_view(vups, view)
	local changed = false
	local bottom_id = nil
	local len = view.get_item_count()
	-- Reconcile in reverse order. This will ensure higher reconcile_ids are
	-- always at top of stack, making GC easier later.
	for i = len, 1, -1 do
		local item = view.get_item(i)
		if #item == 0 then
			error("Encountered impossible situation of empty undo item.")
		end
		-- Check for already reconciled
		local reconcile_id = view.get_tag(i, 1, RECONCILE_ID_TAG)
		if reconcile_id then
			local n_reconcile_id = tonumber(reconcile_id)
			if n_reconcile_id then
				if not bottom_id then bottom_id = n_reconcile_id end
			end
			goto continue
		end
		-- Generate a new reconciliation
		changed = true
		local reconciliation = UndoReconciliation:new()
		vups.reconciliations[reconciliation.id] = reconciliation
		view.set_tag(i, 1, RECONCILE_ID_TAG, reconciliation.id)
		-- Tag matching actions
		for j = 1, #item do
			local action = item[j]
			if action.target and action.surface_index then
				local action_key = make_world_key(
					action.target.position,
					action.surface_index,
					action.target.name
				)
				local marker = vups.unreconciled_markers[action_key]
				if marker then
					local tags = reconcile_action(action, action_key, marker)
					if tags then
						view.set_tag(i, j, THINGS_TAGS, tags)
						reconciliation:add_marker(marker:clone())
					end
				end
			end
		end

		::continue::
	end

	return changed, bottom_id or NINF
end

---Get the top markers from a view of the undo or redo stack.
---@param vups things.VirtualUndoPlayerState
---@param view Core.UndoRedoStackView
---@param tops {[Core.WorldKey]: things.UndoMarker}
local function get_tops(vups, view, tops)
	local len = view.get_item_count()
	if len > 0 then
		local top_reconciliation_id = view.get_tag(1, 1, RECONCILE_ID_TAG)
		if top_reconciliation_id then
			local n_top_reconciliation_id = tonumber(top_reconciliation_id)
			if n_top_reconciliation_id then
				local top_reconciliation = vups.reconciliations[n_top_reconciliation_id]
				if top_reconciliation then
					for _, marker in pairs(top_reconciliation.markers) do
						tops[marker.key] = marker
					end
				end
			end
		end
	end
end

---Reconcile the ingame undo stack with the virtualized marker data. Creates
---tags on the undo stack pickling the marker data to the greatest extent
---possible.
function VirtualUndoPlayerState:perform_reconcile()
	local player = game.get_player(self.player_index)
	if not player or not player.valid then return end
	local urs = player.undo_redo_stack
	local ulen = urs.get_undo_item_count()
	local rlen = urs.get_redo_item_count()
	debug_log(
		"Reconcile for player",
		self.player_index,
		"undo stack",
		ulen > 0 and urs.get_undo_item(1) or "EMPTY",
		"redo stack",
		rlen > 0 and urs.get_redo_item(1) or "EMPTY"
	)
	self.last_reconcile_ticks_played = game.ticks_played

	-- Reconcile undo and redo stacks
	local undo_view, redo_view =
		urs_lib.make_undo_stack_view(urs), urs_lib.make_redo_stack_view(urs)
	local changed_undo, bottom_undo = reconcile_view(self, undo_view)
	local changed_redo, bottom_redo = reconcile_view(self, redo_view)
	local changed = changed_undo or changed_redo
	local rock_bottom = math.min(bottom_undo, bottom_redo)

	-- update tops set
	-- TODO: optimize by checking if top indices changed
	self.top_marker_set = {}
	get_tops(self, undo_view, self.top_marker_set)
	get_tops(self, redo_view, self.top_marker_set)

	-- TODO: Garbage collection is required here. Theoretically, anything lower
	-- than the rock bottom of the two stacks can be GC'd.

	-- After reconcile, destroy all unreconciled markers
	for _, marker in pairs(self.unreconciled_markers) do
		marker:destroy()
	end
	self.unreconciled_markers = {}

	debug_log(
		"Reconcile complete for player",
		self.player_index,
		"top markers:",
		self.top_marker_set
	)
end

---@param action UndoRedoAction
---@param tags Tags
local function apply_undo_action(action, tags)
	if action.type == "removed-entity" and tags["destroyed"] then
		local thing = get_thing(tags["destroyed"] --[[@as int]])
		if thing then thing:is_undo_ghost() end
	end
end

local function apply_reconciled_undo_actions(actions)
	for i = 1, #actions do
		local action = actions[i]
		local tags = action.tags
		if not tags then goto continue end
		tags = tags[THINGS_TAGS] --[[@as Tags?]]
		if not tags then goto continue end
		apply_undo_action(action, tags)
		::continue::
	end
end

---@param actions UndoRedoAction[]
---@param markers {[Core.WorldKey]: things.UndoMarker}
local function apply_unreconciled_undo_actions(actions, markers)
	for i = 1, #actions do
		local action = actions[i]
		if action.target and action.surface_index then
			local action_key = make_world_key(
				action.target.position,
				action.surface_index,
				action.target.name
			)
			local marker = markers[action_key]
			if marker then
				local tags = reconcile_action(action, action_key, marker)
				if tags then apply_undo_action(action, tags) end
			end
		end
	end
end

---@param actions UndoRedoAction[]
---@param markers {[Core.WorldKey]: things.UndoMarker}
local function apply_undo_actions(actions, markers)
	if not actions or #actions == 0 then return end
	local tags = actions[1].tags
	if tags and tags[RECONCILE_ID_TAG] then
		apply_reconciled_undo_actions(actions)
	else
		apply_unreconciled_undo_actions(actions, markers)
	end
end

---Apply an undo operation.
---@param actions UndoRedoAction[]
function VirtualUndoPlayerState:on_undo_applied(actions)
	apply_undo_actions(actions, self.unreconciled_markers)
end

---Apply a redo operation.
---@param actions UndoRedoAction[]
function VirtualUndoPlayerState:on_redo_applied(actions)
	apply_undo_actions(actions, self.unreconciled_markers)
end

---Get the VirtualUndoPlayerState for a player index, creating it if needed.
---@param player_index uint The player index.
---@return things.VirtualUndoPlayerState
function _G.get_undo_player_state(player_index)
	local res = storage.player_undo[player_index]
	if res then return res end
	res = VirtualUndoPlayerState:new(player_index)
	storage.player_undo[player_index] = res
	return res
end

---Determine if an entity might be an undo over a decon marker.
---If so, attempt to restore its Thing identity.
---@param entity LuaEntity A *valid* entity.
---@param key Core.WorldKey The entity's world key.
---@param player LuaPlayer
---@return things.Thing?
function _G.maybe_undo(entity, key, player)
	local vups = get_undo_player_state(player.index)
	if not vups then return nil end
	local marker = vups:get_top_marker(key)
	if (not marker) or (marker.marker_type ~= "deconstruction") then
		return nil
	end
	local thing = get_thing(marker.thing_id)
	if thing and thing:undo_with(entity) then return thing end
end

function _G.debug_undo_stack(player, player_index)
	if not player then player = game.get_player(player_index) end
	if not player or not player.valid then return end
	local urs = player.undo_redo_stack
	local vups = get_undo_player_state(player.index)
	if not vups then return end
	if urs.get_undo_item_count() > 0 then
		debug_log("Top undo item:", urs.get_undo_item(1))
	end
end
