-- Mass operation for when undo/redo is applied

local class = require("lib.core.class").class
local mo_lib = require("control.infrastructure.mass-operation")

local lib = {}

---@class (exact) things.UndoApplication: things.MassOperation
---@field public undo_state things.VirtualUndoPlayerState The undo state associated with this operation.
local UndoApplication = class("things.UndoApplication", mo_lib.MassOperation)
_G.UndoApplication = UndoApplication
lib.UndoApplication = UndoApplication

---@param player LuaPlayer
function UndoApplication:new(player)
	local obj = mo_lib.MassOperation.new(self, "undo") --[[@as things.UndoApplication ]]
	obj.player_index = player.index
	obj.undo_state = get_undo_player_state(player.index)
	debug_log("Created UndoApplication", obj.id, "for player", player.index)
	return obj
end

---@param op things.ConstructionOperation
---@return boolean #True if this is a plausible undo operation and the data was populated, false otherwise.
local function populate_undo_operation_info(op)
	if op.prebuilt then return false end
	if not op.player then return false end
	local vups = get_undo_player_state(op.player_index)
	local marker = vups:get_top_marker(op.key)
	if (not marker) or (marker.marker_type ~= "deconstruction") then
		return false
	end
	local thing = get_thing(marker.thing_id)
	if (not thing) or (not thing:is_tombstone()) then return false end
	op.vups = vups
	op.undo_marker = marker
	op.thing = thing
	return true
end

-- Thing is really part of this undo operation.
local function really_include(self, op)
	local vups = op.vups
	local marker = op.marker
	local thing = op.thing
	debug_log("UndoApplication", self.id, "reviving Thing", thing.id)
	thing:set_entity(op.entity, op.key)
	thing:apply_status()
end

---@param op things.ConstructionOperation
---@param dry_run boolean?
---@return boolean
function UndoApplication:include(op, dry_run)
	-- Only include construction operations owned by this player.
	if op.player_index ~= self.player_index then return false end
	if not populate_undo_operation_info(op) then return false end

	if not dry_run then really_include(self, op) end
	return true
end

---@param actions UndoRedoAction[]
function UndoApplication:complete(actions)
	debug_log("UndoApplication complete")
	self.undo_state:recompute_top_set()
end

---@param op things.ConstructionOperation
---@return things.UndoApplication?
function lib.maybe_begin_undo_operation(op)
	if not populate_undo_operation_info(op) then return nil end
	local app = UndoApplication:new(op.player)
	debug_log(
		"maybe_begin_undo_operation: beginning mass_op",
		app,
		"from single_op",
		op
	)
	really_include(app, op)
	return app
end

return lib
