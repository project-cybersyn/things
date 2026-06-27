--------------------------------------------------------------------------------
-- IMPOSE TAGS OP
--------------------------------------------------------------------------------

local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")
local tlib = require("lib.core.table")

local lib = {}

---@class things.ImposeTagsOp: things.Op
---@field entity? LuaEntity Originally-detected overlapping entity. (May be invalid after construction frame completes; must be checked.)
---@field pos MapPosition Position of the overlap.
---@field key Core.WorldKey World key of the overlap.
---@field overlapped_tags Tags? Pre-overlap Tags of the overlapped Thing, if any.
---@field imposed_tags Tags? Tags imposed on the overlapped Thing, if any.
---@field skip true? `true` if the overlap is to be skipped due to invalidity or consolidation.
local ImposeTagsOp = class("things.ImposeTagsOp", op_lib.Op)
lib.ImposeTagsOp = ImposeTagsOp

---@param player_index int?
---@param entity LuaEntity
---@param key Core.WorldKey
---@param overlapped_thing_id int64
---@param overlapped_tags Tags?
---@param imposed_tags Tags?
function ImposeTagsOp:new(
	player_index,
	entity,
	key,
	overlapped_thing_id,
	overlapped_tags,
	imposed_tags
)
	local obj = op_lib.Op.new(self, op_lib.OpType.IMPOSE_TAGS, key) --[[@as things.ImposeTagsOp]]
	obj.player_index = player_index
	obj.entity = entity
	obj.thing_id = overlapped_thing_id
	if overlapped_tags then
		obj.overlapped_tags = tlib.deep_copy(overlapped_tags)
	end
	if imposed_tags then obj.imposed_tags = tlib.deep_copy(imposed_tags) end
	return obj
end

function ImposeTagsOp:catalogue(frame)
	if self.skip then return end
	local overlapped = self.entity

	if
		not overlapped
		or not overlapped.valid
		or (overlapped.status == defines.entity_status.marked_for_deconstruction)
	then
		self.skip = true
		strace.debug(
			frame.debug_string,
			"ImposeTagsOp:catalogue: overlapped entity is invalid or marked for deconstruction; skipping"
		)
		return
	end

	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then
		self.skip = true
		strace.warn(
			frame.debug_string,
			"ImposeTagsOp:catalogue: no Thing found for overlapped entity; skipping"
		)
		return
	end
end

function ImposeTagsOp:apply(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then
		error(
			"ImposeTagsOp:apply: Thing found in catalogue phase is missing in apply phase. This should be impossible and indicates an event order leak somewhere."
		)
	end
	-- Impose tags
	overlapped_thing:set_tags(self.imposed_tags, true)
end

function ImposeTagsOp:apply_undo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	-- Revert tags
	overlapped_thing:set_tags(self.overlapped_tags, true)
end

function ImposeTagsOp:apply_redo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	-- Reapply tags
	overlapped_thing:set_tags(self.imposed_tags, true)
end

function ImposeTagsOp:dehydrate_for_undo()
	if self.skip then return false end
	self.entity = nil
	return true
end

return lib
