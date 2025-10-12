local class = require("lib.core.class")
local event = require("lib.core.event")

local lib = {}

---@class things.UndoMarkerSet
---@field public deconstructions {[Core.WorldKey]: things.Id} Map from world keys to thing ids for things marked for deconstruction.
---@field public reorientations {[Core.WorldKey]: [things.Id, Core.Orientation]} Map from world keys to thing ids and previous orientations for undoable reorientation operations.
---@field public reconfigurations {[Core.WorldKey]: [things.Id, string]} Map from world keys to thing ids and previous configuration names for undoable reconfiguration operations.

---@class things.PlayerUndoState
local PlayerUndoState = class("things.PlayerUndoState")
lib.PlayerUndoState = PlayerUndoState

function PlayerUndoState:new(player_index)
	local obj = {}
	setmetatable(obj, self)
	obj.player_index = player_index
	return obj
end

function PlayerUndoState:destroy() end

return lib
