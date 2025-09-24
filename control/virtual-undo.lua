local class = require("lib.core.class").class

-- Virtualized undo/redo
-- Ghosts built by undo have player indices

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

---@class things.VirtualUndoRecord
---@field public id int Unique id of this record.
---@field public world_key_to_thing_id {[string]: uint} Map from world keys to Thing ids that are deconstructed in this record.
local VirtualUndoRecord = class("things.VirtualUndoRecord")
_G.VirtualUndoRecord = VirtualUndoRecord

---@class things.VirtualUndoPlayerState
---@field public player_index uint The player index this state is for.
---@field public records {[uint]: things.VirtualUndoRecord} All virtual undo records by their id.
---@field public undo_stack uint[] The virtual undo stack by record id.
---@field public redo_stack uint[] The virtual redo stack by record id.
---@field public possible_tombstones {[string]: uint} Map from world keys to Thing ids that are possible tombstones caused by this player since last reconcile.
local VirtualUndoPlayerState = class("things.VirtualUndoPlayerState")
_G.VirtualUndoPlayerState = VirtualUndoPlayerState

---Reconcile the ingame undo stack with the virtualized one.
function VirtualUndoPlayerState:reconcile()
	local player = game.get_player(self.player_index)
	if not player or not player.valid then return end
	local urs = player.undo_redo_stack

	-- After reconcile, clear possible tombstones
	self.possible_tombstones = {}
end
