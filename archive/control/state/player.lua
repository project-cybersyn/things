local class = require("lib.core.class").class
local event = require("lib.core.event")

local PlayerUndoState = require("control.state.undo").PlayerUndoState

local lib = {}

---State specific to a player.
---@class things.PlayerState
---@field public player_index uint The player index.
---@field public undo things.PlayerUndoState
---@field public prebuild_t int64 The tick at which prebuild state was last updated.
---@field public prebuilt_key_set {[Core.WorldKey]: true} Set of world keys corresponding to objects pre_built on the current tick_played.
local PlayerState = class("things.PlayerState")
lib.PlayerState = PlayerState

function PlayerState:new(player_index)
	local obj = {}
	setmetatable(obj, self)
	obj.player_index = player_index
	obj.undo = PlayerUndoState:new(player_index)
	return obj
end

function PlayerState:destroy() self.undo:destroy() end

---Mark a world key as prebuilt by this player this tick.
---@param key Core.WorldKey The world key to mark.
function PlayerState:mark_key_as_prebuilt(key)
	-- Garbage-collect keys from prior ticks.
	local n = game.ticks_played
	if self.prebuild_t ~= n then
		self.prebuilt_key_set = {}
		self.prebuild_t = n
	end
	self.prebuilt_key_set[key] = true
end

---Determine if a world key was prebuilt this tick.
---@param key Core.WorldKey The world key to check.
---@return boolean
function PlayerState:was_key_prebuilt(key)
	local n = game.ticks_played
	if self.prebuild_t ~= n then return false end
	return self.prebuilt_key_set[key] == true
end

event.bind("on_player_removed", function(ev)
	local ps = storage.players[ev.player_index]
	if ps then
		ps:destroy()
		storage.players[ev.player_index] = nil
	end
end)

function _G.get_player_state(player_index)
	local res = storage.players[player_index]
	if res then return res end
	local player = game.get_player(player_index)
	if not player then error("get_player_state: Invalid player index") end
	res = PlayerState:new(player_index)
	storage.players[player_index] = res
	return res
end

return lib
