-- Collection of Ops, filtered by type.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local op_lib = require("control.op.op")

local OpType = op_lib.OpType

local lib = {}

---@class things.OpSet
---@field public by_index things.Op[]
---@field public by_type table<things.OpType, things.Op[]>
---@field public by_key table<Core.WorldKey, things.Op[]>
---@field public stored_id? int64 ID of stored OpSet in storage, if any.
local OpSet = class("things.OpSet")
lib.OpSet = OpSet

---@param ops? things.Op[]
function OpSet:new(ops)
	local obj
	if not ops then
		ops = {
			by_index = {},
			by_type = {},
			by_key = {},
		}
	else
		obj = {
			by_index = tlib.assign({}, ops),
			by_type = tlib.group_by(ops, function(op) return op.type end),
			by_key = tlib.group_by(ops, function(op) return op.key end),
		}
	end
	setmetatable(obj, self)
	return obj
end

---@param op things.Op
function OpSet:add(op)
	local index_list = self.by_index
	index_list[#index_list + 1] = op
	local type_list = self.by_type[op.type]
	if not type_list then
		type_list = {}
		self.by_type[op.type] = type_list
	end
	type_list[#type_list + 1] = op
	if op.key then
		local key_list = self.by_key[op.key]
		if not key_list then
			key_list = {}
			self.by_key[op.key] = key_list
		end
		key_list[#key_list + 1] = op
	end
end

---@param filter_fn fun(op: things.Op): boolean
---@return things.OpSet
function OpSet:filter(filter_fn)
	local new_ops = tlib.filter(self.by_index, filter_fn)
	return OpSet:new(new_ops)
end

---Get a set of Thing IDs affected by operations in this OpSet.
---@return table<uint64, boolean> #Set of Thing IDs.
function OpSet:get_thing_set()
	local thing_ids = {}
	local ops = self.by_index
	for i = 1, #ops do
		local op = ops[i]
		if op.thing_id then thing_ids[op.thing_id] = true end
	end
	return thing_ids
end

---Get a set of player indices involved in operations in this OpSet.
---@return table<uint, boolean> #Set of player indices.
function OpSet:get_player_set()
	local player_indices = {}
	local ops = self.by_index
	for i = 1, #ops do
		local op = ops[i]
		if op.player_index then player_indices[op.player_index] = true end
	end
	return player_indices
end

return lib
