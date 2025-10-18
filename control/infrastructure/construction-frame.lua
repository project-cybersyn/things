local class = require("lib.core.class").class
local events = require("lib.core.event")

local type = type

local lib = {}

---@alias things.ConstructionFramePrebuildRecord uint|{[uint]: true}

---@class things.ConstructionFrame
---@field public t uint64 The tick_played at which this frame was created.
---@field public prebuild table<Core.WorldKey, things.ConstructionFramePrebuildRecord> Prebuild records by world key.
local ConstructionFrame = class("things.ConstructionFrame")
lib.ConstructionFrame = ConstructionFrame

function ConstructionFrame:new(tick_played)
	local obj = {}
	setmetatable(obj, self)
	obj.t = tick_played
	obj.prebuild = {}
	storage.construction_frames[tick_played] = obj
	debug_log("Began construction frame", tick_played)
	events.dynamic_subtick_trigger(
		"construction_frame",
		"construction_frame",
		obj
	)
	events.raise("construction_frame_begin", obj)
	return obj
end

---Mark a world key as prebuilt by a player in this construction frame.
---@param key Core.WorldKey The world key to mark.
---@param player_index uint The player index who prebuilt the object.
function ConstructionFrame:mark_prebuild(key, player_index)
	local prebuild = self.prebuild
	local record = prebuild[key]
	if not record then
		prebuild[key] = player_index
		return
	elseif type(record) == "number" then
		if record == player_index then return end
		prebuild[key] = { [record] = true, [player_index] = true }
		return
	else
		record[player_index] = true
		return
	end
end

---Check if a world key was prebuilt in this construction frame.
---@param key Core.WorldKey
---@param player_index? uint If given, the player index to check for. If omitted, checks if any player prebuilt the key.
---@return boolean
function ConstructionFrame:is_prebuilt(key, player_index)
	local record = self.prebuild[key]
	if not record then return false end
	if not player_index then return true end
	if type(record) == "number" then
		return record == player_index
	else
		return record[player_index] == true
	end
end

function ConstructionFrame:destroy() storage.construction_frames[self.t] = nil end

function ConstructionFrame:on_subtick()
	debug_log("Ending construction frame", self.t, "at tick", game.ticks_played)
	events.raise("construction_frame_end", self)
	debug_log("Ended construction frame", self.t, "at tick", game.ticks_played)
end

events.register_dynamic_handler(
	"construction_frame",
	---@param frame things.ConstructionFrame
	function(_, frame) frame:on_subtick() end
)

local function gc_frames(t0)
	for t, frame in pairs(storage.construction_frames) do
		if t < t0 then
			debug_log("GC: destroying construction frame", t)
			frame:destroy()
		end
	end
end

---Get the current ConstructionFrame
---@return things.ConstructionFrame
function lib.get_construction_frame()
	local t = game.ticks_played
	local frame = storage.construction_frames[t]
	if frame then return frame end
	gc_frames(t)
	return ConstructionFrame:new(t)
end

return lib
