-- Paste settings op

local op_lib = require("control.op.op")
local class = require("lib.core.class").class
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")
local oclass_lib = require("lib.core.orientation.orientation-class")
local orientation_lib = require("lib.core.orientation.orientation")
local tlib = require("lib.core.table")

local get_by_id = thing_lib.get_by_id
local o_stringify = orientation_lib.stringify
local o_loose_eq = orientation_lib.loose_eq
local PASTE_SETTINGS = op_lib.OpType.PASTE_SETTINGS

local lib = {}

---@class things.PasteSettingsOp: things.Op
---@field overlapped_tags Tags? Tags of the overlapped Thing, if any.
---@field imposed_tags Tags? Tags imposed on the overlapped Thing, if any.
---@field skip true? `true` if the op is to be skipped due to invalidity or consolidation.
local PasteSettingsOp = class("things.PasteSettingsOp", op_lib.Op)
lib.PasteSettingsOp = PasteSettingsOp

---@param player_index int
---@param overlapped_thing_id int64
---@param overlapped_tags Tags?
---@param imposed_tags Tags?
function PasteSettingsOp:new(
	player_index,
	overlapped_thing_id,
	overlapped_tags,
	imposed_tags
)
	local obj = op_lib.Op.new(self, PASTE_SETTINGS) --[[@as things.PasteSettingsOp]]
	obj.player_index = player_index
	obj.thing_id = overlapped_thing_id
	if overlapped_tags then
		obj.overlapped_tags = tlib.deep_copy(overlapped_tags)
	end
	if imposed_tags then obj.imposed_tags = tlib.deep_copy(imposed_tags) end
	return obj
end

function PasteSettingsOp:apply(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then
		error(
			"PasteSettingsOp:apply: Thing found in catalogue phase is missing in apply phase. This should be impossible and indicates an event order leak somewhere."
		)
	end
	-- Impose tags
	overlapped_thing:set_tags(self.imposed_tags, true)
end

function PasteSettingsOp:apply_undo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	-- Revert tags
	overlapped_thing:set_tags(self.overlapped_tags, true)
end

function PasteSettingsOp:apply_redo(frame)
	local overlapped_thing = thing_lib.get_by_id(self.thing_id)
	if not overlapped_thing then return end
	-- Reapply tags
	overlapped_thing:set_tags(self.imposed_tags, true)
end

function PasteSettingsOp:dehydrate_for_undo() return true end

return lib
