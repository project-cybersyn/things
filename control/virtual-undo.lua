local class = require("lib.core.class").class
local scheduler = require("lib.core.scheduler")
local world_state = require("lib.core.world-state")
local urs_lib = require("lib.core.undo-redo-stack")

local function unref_tombstone(key)
	local tombstone = storage.tombstones[key]
	if not tombstone then return end
	tombstone.refcount = tombstone.refcount - 1
	if tombstone.refcount <= 0 then
		storage.tombstones[key] = nil
		-- TODO: deref event
	end
end

-- Virtualized undo/redo
--

-- When something undoable occurs, store in a UndoableThing map from (pos,type) to Thing id.
-- Then, on the next tick, check the player's undo stack.

-- When checking undo stacks, check first for a VirtualID on the top undo
-- item. If we already have one, we know the stack. Otherwise, virtualize
-- the stack, mapping from stack entity descriptions into the UndoableThing map.
-- After virtualizing all unvirtualized stack entries, we can clear the UndoableThing map to save storage/memory.

-- When a ghost is built, check the virtual top of the undo stack for a matching
-- tombstone! If found, flag the ghost as Sus pending the undo/redo event.

-- Virtual undo stack must be an actual stack
-- Only pop from virtual undo stack when an undo is applied that matches the top of the stack

---@class (exact) things.UndoTombstone: Core.WorldState
---@field public thing_id uint The Thing id of the tombstone.
---@field public refcount uint The current reference count for this tombstone.

---@alias things.VirtualUndoRecord {[Core.WorldKey]: things.UndoTombstone}

---@class (exact) things.VirtualUndoPlayerState
---@field public player_index uint The player index this state is for.
---@field public undo_stack things.VirtualUndoRecord[] The virtual undo stack.
---@field public redo_stack things.VirtualUndoRecord[] The virtual redo stack.
---@field public unreconciled_tombstones {[Core.WorldKey]: things.UndoTombstone} Map from world keys to possible tombstones caused by this player since last reconcile.
---@field public reconcile_task int? The scheduled task id for the next reconcile, if any.
local VirtualUndoPlayerState = class("things.VirtualUndoPlayerState")
_G.VirtualUndoPlayerState = VirtualUndoPlayerState

function VirtualUndoPlayerState:new(player_index)
	local obj = setmetatable({}, self)
	obj.player_index = player_index
	obj.undo_stack = {}
	obj.redo_stack = {}
	obj.unreconciled_tombstones = {}
	return obj
end

---Get the matching tombstone for this key as if for a ghost resulting from
---an undo/redo op.
---@param key Core.WorldKey
---@return things.UndoTombstone?
function VirtualUndoPlayerState:has_tombstone(key)
	if self.unreconciled_tombstones[key] then
		return self.unreconciled_tombstones[key]
	end
	local record = self.undo_stack[1]
	if record then return record[key] end
	record = self.redo_stack[1]
	if record then return record[key] end
end

---Mark an entity or ghost as a possible tombstone, and mark the state as
---needing reconciliation.
---@param entity_or_ghost LuaEntity A *valid* entity or ghost.
---@param thing_id uint The Thing id of the entity being deconstructed.
function VirtualUndoPlayerState:create_tombstone(entity_or_ghost, thing_id)
	if not entity_or_ghost.valid then return end
	local tombstone = world_state.get_world_state(entity_or_ghost)
	local key = tombstone.key
	-- Already exists and marked as possible tombstone
	if self.unreconciled_tombstones[key] then return end
	-- Already exists globally as a tombstone
	local preexisting_tombstone = storage.tombstones[key]
	if preexisting_tombstone then
		self.unreconciled_tombstones[key] = preexisting_tombstone
		preexisting_tombstone.refcount = preexisting_tombstone.refcount + 1
	else
		---@cast tombstone things.UndoTombstone
		tombstone.thing_id = thing_id
		tombstone.refcount = 1
		storage.tombstones[key] = tombstone
		self.unreconciled_tombstones[key] = tombstone
	end
	self:reconcile()
end

---Schedule a reconcile if one isn't already scheduled.
function VirtualUndoPlayerState:reconcile()
	if self.reconcile_task then return end
	self.reconcile_task = scheduler.at(game.tick + 1, "reconcile", self)
end

-- Handler for scheduled reconcile tasks
scheduler.register_handler("reconcile", function(task)
	local obj = task.data --[[@as things.VirtualUndoPlayerState]]
	obj.reconcile_task = nil
	obj:perform_reconcile()
end)

---@param view Core.UndoRedoStackView
---@param virtual_stack things.VirtualUndoRecord[]
---@param unreconciled_tombstones {[Core.WorldKey]: things.UndoTombstone}
local function reconcile_view(view, virtual_stack, unreconciled_tombstones)
	local len = view.get_item_count()
	local n_unreconciled = 0
	for i = 1, len do
		local item = view.get_item(i)
		if #item == 0 then
			error("Encountered impossible situation of empty undo item.")
		end
		if view.get_tag(i, 1, "things-reconciled") then
			-- Reached a reconciled item; we can stop.
			break
		end
		n_unreconciled = i
	end
	for i = n_unreconciled, 1, -1 do
		local item = view.get_item(i)
		---@type things.VirtualUndoRecord
		local new_undo_record = {}
		for j, action in pairs(item) do
			if action.type == "removed-entity" and action.surface_index then
				local key = world_state.make_key(
					action.target.position,
					action.surface_index,
					action.target.name
				)
				local tombstone = unreconciled_tombstones[key]
				if tombstone then
					debug_log(
						"perform_reconcile: matched removed-entity action to tombstone",
						key,
						tombstone
					)
					-- Mark this action with the tombstone Thing id
					view.set_tag(i, j, "things-id", tombstone.thing_id)
					new_undo_record[key] = tombstone
					tombstone.refcount = tombstone.refcount + 1
				else
					debug_log(
						"perform_reconcile: removed-entity action has no matching tombstone",
						key,
						action
					)
				end
			end
		end
		table.insert(virtual_stack, 1, new_undo_record)
		view.set_tag(i, 1, "things-reconciled", true)
	end

	-- Clear undo records beyond len
	while #virtual_stack > len do
		local last = virtual_stack[#virtual_stack]
		virtual_stack[#virtual_stack] = nil
		-- Deref tombstones in last
		for key in pairs(last) do
			unref_tombstone(key)
		end
	end
end

---Reconcile the ingame undo stack with the virtualized one.
function VirtualUndoPlayerState:perform_reconcile()
	local player = game.get_player(self.player_index)
	if not player or not player.valid then return end
	local urs = player.undo_redo_stack
	local len = urs.get_undo_item_count()
	debug_log(
		"Reconcile for player",
		self.player_index,
		"undo stack",
		len > 0 and urs.get_undo_item(1) or "EMPTY"
	)

	-- Reconcile the undo stack
	reconcile_view(
		urs_lib.make_undo_stack_view(urs),
		self.undo_stack,
		self.unreconciled_tombstones
	)
	-- Reconcile the redo stack
	reconcile_view(
		urs_lib.make_redo_stack_view(urs),
		self.redo_stack,
		self.unreconciled_tombstones
	)

	-- After reconcile, remove possible_tombstones from refcount and clear it
	for key in pairs(self.unreconciled_tombstones) do
		unref_tombstone(key)
	end
	self.unreconciled_tombstones = {}
end

---Apply an undo operation.
function VirtualUndoPlayerState:on_undo_applied(actions)
	-- TODO: verify correspondence between actions and top of undo stack
	---@type things.VirtualUndoRecord
	local record = table.remove(self.undo_stack, 1)
	if not record then return end
	for key, tombstone in pairs(record) do
		local thing = get_thing(tombstone.thing_id)
		if thing then thing:is_undo_ghost() end
		unref_tombstone(key)
	end
end

---Apply a redo operation.
function VirtualUndoPlayerState:on_redo_applied(actions)
	-- TODO: verify correspondence between actions and top of redo stack
	---@type things.VirtualUndoRecord
	local record = table.remove(self.redo_stack, 1)
	if not record then return end
	for key, tombstone in pairs(record) do
		local thing = get_thing(tombstone.thing_id)
		if thing then thing:is_undo_ghost() end
		unref_tombstone(key)
	end
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
