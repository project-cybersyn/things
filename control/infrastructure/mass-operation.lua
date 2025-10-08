local class = require("lib.core.class").class
local counters = require("lib.core.counters")
local event = require("lib.core.event")

local lib = {}

event.register_dynamic_handler(
	"mass_op_subtick",
	---@param mass_op things.MassOperation
	function(ev, mass_op) mass_op:on_subtick() end
)

---A bulk operation involving multiple simultaneous
---individual operations.
---@class things.MassOperation
---@field public id int64 Unique identifier for this MassOperation.
---@field public type string Type of this mass operation.
---@field public ticks_played uint64 The unpaused game tick when this MassOperation was created.
---@field public player_index? uint The index of the player who initiated this MassOperation, if any.
---@field public subtick_trigger boolean? Whether a subtick event has been scheduled for this MassOperation.
local MassOperation = class("things.MassOperation")
lib.MassOperation = MassOperation

---Create a new MassOperation.
---@param type string Type of this mass operation.
---@return things.MassOperation
function MassOperation:new(type)
	local obj = setmetatable({ type = type }, self)
	obj.id = counters.next("mass_op")
	obj.ticks_played = game.ticks_played
	storage.mass_ops[obj.id] = obj
	return obj
end

---Destroy a MassOperation
function MassOperation:destroy() storage.mass_ops[self.id] = nil end

---Trigger an event that will happen on the next subtick. This can be used to
---artifically generate a "mass operation ended" event when the game otherwise
---does not provide one.
---@param multiple boolean? If true, multiple subtick events per operation may be scheduled; otherwise, only trigger once.
function MassOperation:trigger_subtick_event(multiple)
	if self.subtick_trigger and not multiple then return end
	event.dynamic_subtick_trigger("mass_op_subtick", "subtick", self)
	self.subtick_trigger = true
end

---Called as a result of an earlier `trigger_subtick_event` request.
function MassOperation:on_subtick() self:destroy() end

---Include the given individual operation in this mass operation.
---@param operation things.Operation
---@param dry_run boolean? If true, do not actually include the operation, just check if it would be possible.
---@return boolean #True if the operation was (or would be) included, false otherwise.
function MassOperation:include(operation, dry_run)
	-- Default no-op; override in subclasses
	return false
end

---Get the first MassOperation of the given type for the given player on
---the given tick_played. If any parameter is nil, it is ignored.
---@param ty string|nil The type of MassOperation to look for.
---@param player_index uint|nil The index of the player who initiated the MassOperation.
---@param tick uint64|nil The tick_played value of the MassOperation.
---@return things.MassOperation?
function lib.find(ty, player_index, tick)
	for _, op in pairs(storage.mass_ops) do
		if
			((not ty) or op.type == ty)
			and ((not player_index) or op.player_index == player_index)
			and ((not tick) or op.ticks_played == tick)
		then
			return op
		end
	end
	return nil
end

---Attempt to include the given Operation in all MassOperations on the given
---tick
---@param operation things.Operation
---@param tick uint64|nil The tick_played value of the MassOperation.
---@return boolean #True if the operation was included in any MassOperation, false otherwise.
function lib.try_include_in_all(operation, tick)
	local included = false
	for _, op in pairs(storage.mass_ops) do
		if (not tick) or op.ticks_played == tick then
			if op:include(operation) then included = true end
		end
	end
	return included
end

return lib
