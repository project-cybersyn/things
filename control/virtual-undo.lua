local class = require("lib.core.class").class
local scheduler = require("lib.core.scheduler")
local world_state = require("lib.core.world-state")
local urs_lib = require("lib.core.undo-redo-stack")
local counters = require("lib.core.counters")
local mconst = require("lib.core.math.constants")

local INF = mconst.BIG_INT
local NINF = mconst.BIG_NEG_INT

local get_world_key = world_state.get_world_key

-- Virtualized undo/redo
--
-- The general idea of this code is that when an undoable action occurs, we
-- need to know which if any Things were involved. Unfortunately, Factorio's
-- paucity of events and information, along with imo backwards event ordering
-- makes this a massively difficult problem.
--
-- Credit for various ideas in fixing this goes to hgschmie's Fiber Optics
-- mod and Telkine2018's Compact Circuits mod, both of whom contain partial
-- versions of this idea. My goal here was to make a fully general working
-- implementation. All code is newly written.
--
-- The things we need to achieve are:
-- 1) When an entity is destroyed by an undoable action, tag the action
-- with the Thing id and pickle the Thing for later restoration.
-- 2) When a ghost is built, was it the result of an undo recorded in (1)? If
-- so, restore its Thing-ness; if not, treat as new construction.
--
-- Complications with (1) include that there is no event whatsoever for when
-- a new entry is added to the undo stack. We can only assume (correctly so far)
-- that when an undoable action occurs, by scheduling an event for the *next*
-- tick, the undo stack will have been updated. It turns out undo/redo
-- don't work while tick is paused, so this is reasonably safe. Unfortunately:
-- XXX: If an undo occurs on the very next tick after an undoable action, this code may leak.
-- XXX: If multiple undos somehow occur per tick per player (perhaps via a mod forcing undo?) this code may leak.
--
-- A further complication is that we must engage in bookkeeping to connect the
-- undoable actions and associated Things with the reconciliation process that
-- takes place a tick later. This requires the use of `storage` and a system
-- of "world keys" basically mapping (position, name) tuples to Thing ids.
-- Later, when reconciling the undo/redo stacks, the `action.target` can also
-- be mapped to a world key, and if a Thing id is found, the action can be
-- mapped to the Thing. Unfortunately:
-- XXX: If multiple entities of the same type are destroyed at the same position
-- only one will be recorded for undo purposes. (I'm not sure this is possible)
--
-- The primary complication with step (2) is that ghost building takes place
-- *before* the `on_undo_applied` event, and there is no indications that the
-- ghosts came from the undo. This requires that we once again bookkeep and
-- reconcile between the two events. The kicker here is that if there *isn't*
-- a matching undo, we simply have no way of knowing that because there's no
-- such thing as a "didn't undo" event. We solve this again by waiting until
-- next tick, at which time we assume there wasn't an undo.
-- This creates ample possibility for leaks in the abstraction.
--
-- Furthermore, when a ghost is built, it carries no information about whether
-- it came from an undo (if it e.g. pointed to the undo action that created it that would solve this whole problem) so we
-- must "educated guess" by checking if the ghost's world key matches any of
-- the world keys of items on top of the undo/redo stack. If so, we assume it
-- came from an undo, and mark it as "maybe undo". Then, when either the
-- undo event or tick event comes in, we can finally resolve the situation.
--
-- What this all amounts to is we basically have to rewrite the whole undo
-- system in Lua, piggybacking on `storage` and the undo stack's tags capability
-- for data.
--
-- Anyway, rant over, here's the implementation.

-- "Undo from unreconciled": reconcile "in place" on Undo push

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

---Destroy an undo marker.
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

---Per player virtualized undo/redo system. One of these is stored per player
---id.
---@class (exact) things.VirtualUndoPlayerState
---@field public player_index uint The player index this state is for.
---@field public unreconciled_markers {[Core.WorldKey]: things.UndoMarker} Map from world keys to possible markers caused by this player since last reconcile.
---@field public reconciliations {[int]: things.UndoReconciliation} Reconciliations on the stack, by id.
---@field public top_marker_set {[Core.WorldKey]: things.UndoMarker} Set of world keys at the top of either undo or redo stack as of last reconcile.
---@field public reconcile_task int? The scheduled task id for the next reconcile, if any.
---@field public last_reconcile_ticks_played uint The unpaused tick at which the last reconcile was performed.
local VirtualUndoPlayerState = class("things.VirtualUndoPlayerState")
_G.VirtualUndoPlayerState = VirtualUndoPlayerState

---@param player_index int
function VirtualUndoPlayerState:new(player_index)
	local obj = setmetatable({}, self)
	obj.player_index = player_index
	obj.unreconciled_markers = {}
	obj.reconciliations = {}
	obj.top_marker_set = {}
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

---Schedule a reconcile for the next tick if one isn't already scheduled.
function VirtualUndoPlayerState:reconcile_later()
	if self.reconcile_task then return end
	self.reconcile_task = scheduler.at(game.tick + 1, "reconcile", self)
end

-- Handler for scheduled reconcile tasks
scheduler.register_handler("reconcile", function(task)
	local obj = task.data --[[@as things.VirtualUndoPlayerState]]
	obj.reconcile_task = nil
	obj:perform_reconcile()
end)

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
---@param checklist {[int]: true?} Set of all reconcile IDs; seen ones will be marked nil.
---@param tops {[Core.WorldKey]: things.UndoMarker} All world keys at top of stack will be written here after reconciliation.
---@return int bottom_id Rec.ID at the bottom of the stack.
local function reconcile_view(vups, view, checklist, tops)
	local bottom_id = NINF
	local len = view.get_item_count()
	for i = 1, len do
		local item = view.get_item(i)
		if #item == 0 then
			error("Encountered impossible situation of empty undo item.")
		end
		-- Check for already reconciled
		local reconcile_id = view.get_tag(i, 1, "things-reconcile-id")
		if reconcile_id then
			local n_reconcile_id = tonumber(reconcile_id)
			if n_reconcile_id then
				bottom_id = n_reconcile_id
				checklist[n_reconcile_id] = nil
			end
			goto continue
		end
		-- Generate a new reconciliation
		local reconciliation = UndoReconciliation:new()
		vups.reconciliations[reconciliation.id] = reconciliation
		view.set_tag(i, 1, "things-reconcile-id", reconciliation.id)
		-- Tag matching actions
		for j = 1, #item do
			local action = item[j]
			if action.target and action.surface_index then
				local action_key = world_state.make_key(
					action.target.position,
					action.surface_index,
					action.target.name
				)
				local marker = vups.unreconciled_markers[action_key]
				if marker then
					local tags = reconcile_action(action, action_key, marker)
					if tags then
						view.set_tag(i, j, "things-tags", tags)
						reconciliation:add_marker(marker)
						vups.unreconciled_markers[action_key] = nil
					end
				end
			end
		end

		::continue::
	end

	-- After reconciling, update tops set
	if len > 0 then
		local top_reconciliation_id = view.get_tag(1, 1, "things-reconcile-id")
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

	return bottom_id
end

---Reconcile the ingame undo stack with the virtualized one.
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

	-- Create checklist of all known reconciliations
	local checklist = {}
	for id in pairs(self.reconciliations) do
		checklist[id] = true
	end
	-- Create top_marker_set
	self.top_marker_set = {}

	-- Reconcile undo and redo stacks
	local bottom_undo = reconcile_view(
		self,
		urs_lib.make_undo_stack_view(urs),
		checklist,
		self.top_marker_set
	)
	reconcile_view(
		self,
		urs_lib.make_redo_stack_view(urs),
		checklist,
		self.top_marker_set
	)

	-- XXX: this doesnt work. undo stack can have hidden entries pushed back
	-- onto it via redo. we can only kill stuff that falls off the bottom of the
	-- undo stack.
	-- After reconcile, destroy all reconciliations still on the checklist
	-- These are the ones not seen during reconcile, i.e. dropped off the
	-- undo/redo stack.
	-- for id in pairs(checklist) do
	-- 	local reconciliation = self.reconciliations[id]
	-- 	if reconciliation then
	-- 		debug_log(
	-- 			"Reconcile: dropping reconciliation",
	-- 			id,
	-- 			"for player",
	-- 			self.player_index
	-- 		)
	-- 		reconciliation:destroy()
	-- 		self.reconciliations[id] = nil
	-- 	end
	-- end

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

---@param actions UndoRedoAction[]
local function apply_undo_actions(actions)
	for i = 1, #actions do
		local action = actions[i]
		local tags = action.tags
		debug_log("apply_undo_actions: action", action)
		if not tags then goto continue end
		tags = tags["things-tags"] --[[@as Tags?]]
		if not tags then goto continue end
		apply_undo_action(action, tags)
		::continue::
	end
end

---Apply an undo operation.
---@param actions UndoRedoAction[]
function VirtualUndoPlayerState:on_undo_applied(actions)
	apply_undo_actions(actions)
	self:reconcile_later()
end

---Apply a redo operation.
---@param actions UndoRedoAction[]
function VirtualUndoPlayerState:on_redo_applied(actions)
	apply_undo_actions(actions)
	self:reconcile_later()
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

-- Handler for `later_check_maybe_ghost`
scheduler.register_handler("maybe_ghost_check", function(task)
	storage.tasks["maybe_ghost"] = nil
	local data = task.data --[[@as {[things.Thing]: true}]]
	for thing, _ in pairs(data) do
		thing:isnt_undo_ghost()
	end
end)

---In 1 tick, check if this thing is still a maybe_undo_ghost, and if so,
---notify it that it isn't really an undo ghost.
---@param thing things.Thing
local function later_check_maybe_ghost(thing)
	local task_id = storage.tasks["maybe_ghost"]
	if not task_id then
		storage.tasks["maybe_ghost"] =
			scheduler.at(game.tick + 1, "maybe_ghost_check", { [thing] = true })
	else
		local task = scheduler.get(task_id)
		if task and task.data then task.data[thing] = true end
	end
end

---Determine if a ghost entity might be an undo over a tombstone.
---If so, move the tombstone to a "maybe undo" state and return it.
---@param ghost LuaEntity
---@param player LuaPlayer
---@return things.Thing?
function _G.maybe_undo_tombstone(ghost, player)
	if not ghost.valid or ghost.type ~= "entity-ghost" then return nil end
	local vups = get_undo_player_state(player.index)
	if not vups then return nil end
	local key = get_world_key(ghost)
	debug_log("maybe_undo_tombstone: checking for tombstone at", key)
	local marker = vups:get_top_marker(key)
	if (not marker) or (marker.marker_type ~= "deconstruction") then
		debug_log("maybe_undo_tombstone: no valid marker found")
		return nil
	end
	local thing = get_thing(marker.thing_id)
	if thing and thing:is_maybe_undo_ghost(ghost) then
		later_check_maybe_ghost(thing)
		return thing
	end
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
