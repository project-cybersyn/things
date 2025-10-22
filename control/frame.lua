local class = require("lib.core.class").class
local events = require("lib.core.event")
local opset_lib = require("control.op.opset")
local op_lib = require("control.op.op")
local strace = require("lib.core.strace")
local counters = require("lib.core.counters")

local OpSet = opset_lib.OpSet
local OpType = op_lib.OpType
local type = type
local tunpack = table.unpack

local lib = {}

---@alias things.FramePrebuildRecord uint|{[uint]: true}

---@class things.Frame
---@field public id int64 Unique identifier for this frame.
---@field public t uint64 The tick_played at which this frame was created.
---@field public debug_string string Debug string for frame event logging.
---@field public prebuild table<Core.WorldKey, things.FramePrebuildRecord> Prebuild records by world key.
---@field public resolved table<Core.WorldKey, things.Thing|things.Thing[]> Resolved Things by world key.
---@field public op_set things.OpSet The set of operations in this frame.
---@field public id_counter int64 Counter for generating local operation IDs.
---@field public post_events table[] List of postprocessing functions to run at the end of the frame.
local Frame = class("things.Frame")
lib.Frame = Frame

function Frame:new()
	if storage.current_frame then
		error(
			"Cannot create a new Frame while another is active. Do not call the Frame constructor directly. Use lib.get_frame() instead."
		)
	end
	local t = game.ticks_played
	local id = counters.next("frame")
	local debug_string = string.format("Frame[%d.%d]", t, id)
	local obj = {}
	setmetatable(obj, self)
	obj.id = id
	obj.t = t
	obj.debug_string = debug_string
	obj.prebuild = {}
	obj.resolved = {}
	obj.op_set = OpSet:new()
	obj.id_counter = 0
	obj.post_events = {}

	-- Begin frame
	storage.current_frame = obj
	strace.debug(
		debug_string,
		"*******************BEGIN FRAME*******************"
	)
	events.dynamic_subtick_trigger("frame", "frame", obj)
	events.raise("things.frame_phase_build", obj)
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
	elseif type(record) == "number" then
		if record == player_index then return end
		prebuild[key] = { [record] = true, [player_index] = true }
	else
		record[player_index] = true
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

---Mark a Thing as resolved at a world key in this construction frame.
---@param key Core.WorldKey The world key to mark.
---@param thing things.Thing The Thing resolved at the key.
function Frame:mark_resolved(key, thing)
	local resolved = self.resolved
	local record = resolved[key]
	if not record then
		resolved[key] = thing
	else
		if record.id then
			record = { record }
			resolved[key] = record
		end
		record[#record + 1] = thing
	end
	-- Notify Ops that thing was resolved
	local ops_at_key = self.op_set.by_key[key]
	if ops_at_key then
		for i = 1, #ops_at_key do
			ops_at_key[i]:resolved(key, thing)
		end
	end
end

---Determine if a Thing or Things was resolved at the given key.
---@param key Core.WorldKey
---@return boolean found Whether any Thing was resolved at the key.
---@return things.Thing? unique The resolved Thing, if only one was resolved.
---@return things.Thing[]? multiple The list of resolved Things, if multiple were resolved.
function Frame:get_resolved(key)
	local res = self.resolved[key]
	if not res then
		return false, nil, nil
	elseif res.id then
		return true, res, nil
	else
		return false, nil, res
	end
end

---@param op things.Op
function Frame:add_op(op)
	self.op_set:add(op)
	strace.debug(self.debug_string, "added", OpType[op.type], "op:", op)
end

---Generate a numerical ID unique to this frame.
function Frame:generate_id()
	self.id_counter = self.id_counter + 1
	return self.id_counter
end

---Enqueue an event to be fired when the frame closes.
---@param event_name string Event name to raise. Will be raised using CoreLib `event.raise`.
---@param ... any Arguments to pass to the event.
function Frame:post_event(event_name, ...)
	local pe = self.post_events
	pe[#pe + 1] = { event_name, ... }
end

function Frame:on_subtick()
	self:catalogue_phase()
	self:resolve_phase()
	self:apply_phase()
	self:reconcile_phase()
	self:terminate()
end

---Execute the catalogue phase. This is when ops that may be composite can
---register their sub-ops.
function Frame:catalogue_phase()
	strace.debug(
		self.debug_string,
		"-----------------CATALOGUE PHASE-----------------"
	)
	local ops = self.op_set.by_index
	for i = 1, #ops do
		ops[i]:catalogue(self)
	end
	events.raise("things.frame_phase_catalogue", self)
end

---Execute the resolve phase. This is when ops that may create or identify
---entities should call `Frame:mark_resolved`.
function Frame:resolve_phase()
	strace.debug(
		self.debug_string,
		"-----------------RESOLVE PHASE-----------------"
	)
	local ops = self.op_set.by_index
	for i = 1, #ops do
		ops[i]:resolve(self)
	end
	events.raise("things.frame_phase_resolve", self)
end

function Frame:apply_phase()
	strace.debug(
		self.debug_string,
		"-----------------APPLY PHASE-----------------"
	)
	local ops = self.op_set.by_index
	for i = 1, #ops do
		ops[i]:apply(self)
	end
	events.raise("things.frame_phase_apply", self)
end

function Frame:reconcile_phase()
	strace.debug(
		self.debug_string,
		"-----------------RECONCILE PHASE-----------------"
	)
	local ops = self.op_set.by_index
	for i = 1, #ops do
		ops[i]:reconcile(self)
	end
	events.raise("things.frame_phase_reconcile", self)
end

function Frame:terminate()
	events.raise("things.frame_will_end", self)
	local t = game.ticks_played
	strace.debug(
		self.debug_string,
		"Terminating frame. Frame spanned",
		t - self.t + 1,
		"ticks_played"
	)
	strace.debug(
		self.debug_string,
		"********************END FRAME********************"
	)
	events.raise("things.frame_ended", self)
	storage.current_frame = nil
	-- Run post events
	for _, pe in pairs(self.post_events) do
		strace.debug(self.debug_string, "Raising post-event", pe[1])
		events.raise(tunpack(pe))
	end
end

events.register_dynamic_handler(
	"frame",
	---@param frame things.Frame
	function(_, frame) frame:on_subtick() end
)

---Get the current Frame, creating if needed
---@return things.Frame
function lib.get_frame()
	local frame = storage.current_frame
	if frame then return frame end
	return Frame:new()
end

---Return the current frame if it exists.
---@return things.Frame|nil
function lib.in_frame() return storage.current_frame end

return lib
