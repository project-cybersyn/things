local class = require("lib.core.class").class
local events = require("lib.core.event")
local opset_lib = require("control.op.opset")

local OpSet = opset_lib.OpSet
local type = type

local lib = {}

---@alias things.FramePrebuildRecord uint|{[uint]: true}

---@class things.Frame
---@field public t uint64 The tick_played at which this frame was created.
---@field public prebuild table<Core.WorldKey, things.FramePrebuildRecord> Prebuild records by world key.
---@field public op_set things.OpSet The set of operations in this frame.
---@field public id_counter int64 Counter for generating local operation IDs.
local Frame = class("things.Frame")
lib.Frame = Frame

function Frame:new(tick_played)
	local obj = {}
	setmetatable(obj, self)
	obj.t = tick_played
	obj.prebuild = {}
	obj.op_set = OpSet:new()
	obj.id_counter = 0
	storage.frames[tick_played] = obj
	debug_log("Began frame", tick_played)
	events.dynamic_subtick_trigger("frame", "frame", obj)
	events.raise("things.frame_begin", obj)
	return obj
end

---Mark a world key as prebuilt by a player in this construction frame.
---@param key Core.WorldKey The world key to mark.
---@param player_index uint The player index who prebuilt the object.
function Frame:mark_prebuild(key, player_index)
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
function Frame:is_prebuilt(key, player_index)
	local record = self.prebuild[key]
	if not record then return false end
	if not player_index then return true end
	if type(record) == "number" then
		return record == player_index
	else
		return record[player_index] == true
	end
end

function Frame:destroy() storage.frames[self.t] = nil end

---@param op things.Op
function Frame:add_op(op) self.op_set:add(op) end

---Generate a numerical ID unique to this frame.
function Frame:generate_id()
	self.id_counter = self.id_counter + 1
	return self.id_counter
end

function Frame:on_subtick()
	debug_log("Ending construction frame", self.t, "at tick", game.ticks_played)
	events.raise("things.frame_end", self)
	debug_log("Ended construction frame", self.t, "at tick", game.ticks_played)
end

events.register_dynamic_handler(
	"frame",
	---@param frame things.Frame
	function(_, frame) frame:on_subtick() end
)

local function gc_frames(t0)
	for t, frame in pairs(storage.frames) do
		if t < t0 then
			debug_log("GC: destroying frame", t)
			frame:destroy()
		end
	end
end

---Get the current Frame
---@return things.Frame
function lib.get_frame()
	local t = game.ticks_played
	local frame = storage.frames[t]
	if frame then return frame end
	gc_frames(t)
	return Frame:new(t)
end

return lib
