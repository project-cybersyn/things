local class = require("lib.core.class").class
local events = require("lib.core.event")
local opset_lib = require("control.op.opset")
local op_lib = require("control.op.op")
local strace = require("lib.core.strace")
local counters = require("lib.core.counters")
local urs_lib = require("lib.core.undo-redo-stack")
local constants = require("control.constants")
local ur_util = require("control.util.undo-redo")
local tlib = require("lib.core.table")

local OpSet = opset_lib.OpSet
local OpType = op_lib.OpType
local type = type
local tunpack = table.unpack
local UNDO_TAG = constants.UNDO_TAG
local GHOST_REVIVAL_TAG = constants.GHOST_REVIVAL_TAG
local get_undo_opset_ids = ur_util.get_undo_opset_ids
local tag_undo_item = ur_util.tag_undo_item

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

---@type LuaProfiler
local frame_profiler

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
	strace.info(
		debug_string,
		"vvvvvvvvvvvvvvvvvvvvvvvvvBEGIN FRAMEvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
	)
	frame_profiler = game.create_profiler()
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

---@param op? things.Op
function Frame:add_op(op)
	if not op then return end
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

--------------------------------------------------------------------------------
-- FRAME SUBTICK PHASES
--------------------------------------------------------------------------------

function Frame:on_subtick()
	self:catalogue_phase()
	self:resolve_phase()
	self:apply_phase()
	self:tag_stacks()
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

--------------------------------------------------------------------------------
-- UNDO-REDO
--------------------------------------------------------------------------------

---@param player LuaPlayer
---@param view Core.UndoRedoStackView
---@param seen_ids table<int64, boolean>
---@param forward_op things.UndoOp|things.RedoOp|nil
---@param inverse_op things.UndoOp|things.RedoOp|nil
---@param debug_stackname string
function Frame:tag_view_for_player(
	player,
	view,
	seen_ids,
	forward_op,
	inverse_op,
	debug_stackname
)
	local player_index = player.index
	for i = 1, view.get_item_count() do
		local actions = view.get_item(i)
		local tagged, opset_id, inverse_opset_id =
			get_undo_opset_ids(view, i, actions)
		if opset_id then seen_ids[opset_id] = true end
		if inverse_opset_id then seen_ids[inverse_opset_id] = true end
		if tagged then goto continue_item end
		if i == 1 then
			local filtered_opset = self.op_set:filter(
				function(op)
					return ((op.player_index == nil) or (op.player_index == player_index))
						and op:dehydrate_for_undo()
				end
			)
			local stored_id = filtered_opset:store(player_index)
			local inv_id = inverse_op and inverse_op.opset_id
			tag_undo_item(view, i, actions, stored_id, inv_id)
			seen_ids[stored_id] = true
			if inv_id then seen_ids[inv_id] = true end
			strace.debug(
				self.debug_string,
				"Tagged",
				debug_stackname,
				"item",
				i,
				"for player",
				player_index,
				"with opset IDs (",
				stored_id,
				inv_id,
				")"
			)
		else
			tag_undo_item(view, i, actions, nil, nil)
			strace.debug(
				self.debug_string,
				"Tagged",
				debug_stackname,
				"item",
				i,
				"for player",
				player_index,
				"as having no opset"
			)
		end
		::continue_item::
	end
end

---@param player LuaPlayer
---@param seen_ids table<int64, boolean>
---@param undo_op things.UndoOp|nil
---@param redo_op things.RedoOp|nil
function Frame:tag_undo_stack_for_player(player, seen_ids, undo_op, redo_op)
	local view = urs_lib.make_undo_stack_view(player.undo_redo_stack)
	self:tag_view_for_player(player, view, seen_ids, undo_op, redo_op, "undo")
end

---@param player LuaPlayer
---@param seen_opset_ids table<int64, boolean>
---@param undo_op things.UndoOp|nil
---@param redo_op things.RedoOp|nil
function Frame:tag_redo_stack_for_player(
	player,
	seen_opset_ids,
	undo_op,
	redo_op
)
	local view = urs_lib.make_redo_stack_view(player.undo_redo_stack)
	self:tag_view_for_player(
		player,
		view,
		seen_opset_ids,
		redo_op,
		undo_op,
		"redo"
	)
end

function Frame:tag_stacks()
	strace.debug(
		self.debug_string,
		"-----------------TAG_STACKS PHASE-----------------"
	)
	local player_set = self.op_set:get_player_index_set()
	for player_index, _ in pairs(player_set) do
		local player = game.get_player(player_index)
		if player then
			local seen_opset_ids = {}
			local undo_op = self.op_set:get_pt(player_index, OpType.UNDO) --[[@as things.UndoOp? ]]
			local redo_op = self.op_set:get_pt(player_index, OpType.REDO) --[[@as things.RedoOp? ]]
			self:tag_undo_stack_for_player(player, seen_opset_ids, undo_op, redo_op)
			self:tag_redo_stack_for_player(player, seen_opset_ids, undo_op, redo_op)
			strace.trace(
				self.debug_string,
				"Player",
				player_index,
				"saw opset IDs:",
				function()
					return table.concat(
						tlib.t_map_a(seen_opset_ids, function(_, id) return id end),
						","
					)
				end
			)
			for id, stored_opset in pairs(storage.stored_opsets) do
				if
					stored_opset.stored_player_index == player_index
					and not seen_opset_ids[id]
				then
					strace.debug(
						self.debug_string,
						"Cleaning up unreferenced stored opset: ID",
						id
					)
					stored_opset:unstore()
				end
			end
		end
	end
end

function Frame:terminate()
	events.raise("things.frame_will_end", self)
	local t = game.ticks_played
	log({
		"",
		self.debug_string,
		" ",
		frame_profiler,
		" (",
		t - self.t + 1,
		" ticks)",
	})
	strace.info(
		self.debug_string,
		"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^END FRAME^^^^^^^^^^^^^^^^^^^^^^^^^^^"
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
