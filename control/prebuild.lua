-- Prebuild-build bridging logic.

local class = require("lib.core.class").class

---@class things.PrebuildPlayerState
---@field public player_index uint The player index.
---@field public last_ticks_played uint The last game tick this state was updated.
---@field public prebuilt_key_set {[Core.WorldKey]: true} Set of world keys corresponding to objects pre_built on this tick.
local PrebuildPlayerState = class("things.PrebuildPlayerState")
_G.PrebuildPlayerState = PrebuildPlayerState

function PrebuildPlayerState:new(player_index)
	local obj = {}
	setmetatable(obj, self)
	obj.player_index = player_index
	obj.last_ticks_played = 0
	return obj
end

---Mark a world key as prebuilt this tick.
---@param key Core.WorldKey The world key to mark.
function PrebuildPlayerState:mark_key_as_prebuilt(key)
	local n = game.ticks_played
	if self.last_ticks_played < n then
		self.prebuilt_key_set = {}
		self.last_ticks_played = n
	end
	self.prebuilt_key_set[key] = true
end

---Determine if a world key was prebuilt this tick.
---@param key Core.WorldKey The world key to check.
---@return boolean
function PrebuildPlayerState:was_key_prebuilt(key)
	local n = game.ticks_played
	if self.last_ticks_played < n then return false end
	return self.prebuilt_key_set[key] == true
end

---Get the PrebuildPlayerState for a player index, creating it if needed.
---@param player_index uint The player index.
---@return things.PrebuildPlayerState
function _G.get_prebuild_player_state(player_index)
	local res = storage.player_prebuild[player_index]
	if res then return res end
	res = PrebuildPlayerState:new(player_index)
	storage.player_prebuild[player_index] = res
	return res
end
