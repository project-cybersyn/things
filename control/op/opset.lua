-- Collection of Ops, filtered by type.

local class = require("lib.core.class").class
local tlib = require("lib.core.table")
local op_lib = require("control.op.op")
local counters = require("lib.core.counters")

local OpType = op_lib.OpType

local lib = {}

---@class things.OpSet
---@field public by_index things.Op[]
---@field public by_type table<things.OpType, things.Op[]>
---@field public by_key table<Core.WorldKey, things.Op[]>
---@field public stored_id? int64 ID of stored OpSet in storage, if any.
---@field public stored_player_index? uint Player index of the player who stored this OpSet, if any.
local OpSet = class("things.OpSet")
lib.OpSet = OpSet

---@param ops? things.Op[]
function OpSet:new(ops)
	local obj
	if not ops then
		obj = {
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

local function add_key(opset, key, op)
	local key_list = opset.by_key[key]
	if not key_list then
		key_list = {}
		opset.by_key[key] = key_list
	end
	key_list[#key_list + 1] = op
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
	if op.key then add_key(self, op.key, op) end
	if op.secondary_key then add_key(self, op.secondary_key, op) end
end

---@param filter_fn fun(op: things.Op): boolean
---@return things.OpSet
function OpSet:filter(filter_fn)
	local new_ops = tlib.filter(self.by_index, filter_fn)
	return OpSet:new(new_ops)
end

---Find a unique operation at the given key also matching the given filter.
---@param key Core.WorldKey
---@param filter_fn fun(op: things.Op): boolean
function OpSet:findk_unique(key, filter_fn)
	local key_list = self.by_key[key]
	if not key_list then return nil end
	local found = nil
	for i = 1, #key_list do
		local op = key_list[i]
		if filter_fn(op) then
			if found then return nil end
			found = op
		end
	end
	return found
end

---Find a unique operation of the given type also matching the given filter.
---@param type things.OpType
---@param filter_fn fun(op: things.Op): boolean
function OpSet:findt_unique(type, filter_fn)
	local type_list = self.by_type[type]
	if not type_list then return nil end
	local found = nil
	for i = 1, #type_list do
		local op = type_list[i]
		if filter_fn(op) then
			if found then return nil end
			found = op
		end
	end
	return found
end

---Get the first operation in this OpSet with the given player index and type.
---@param player_index uint
---@param type things.OpType
---@return things.Op|nil
function OpSet:get_pt(player_index, type)
	local bt = self.by_type[type]
	if bt then
		for i = 1, #bt do
			local op = bt[i]
			if op.player_index == player_index then return op end
		end
	end
	return nil
end

---Get the first removal operation in this OpSet with the given key and player index.
---@param key Core.WorldKey
---@param player_index uint
function OpSet:get_removal_op(key, player_index)
	local key_list = self.by_key[key]
	if not key_list then return nil end
	for i = 1, #key_list do
		local op = key_list[i]
		if
			op.player_index == player_index
			and (op.type == OpType.MFD or op.type == OpType.DESTROY)
		then
			return op
		end
	end
	return nil
end

---Get a set of Thing IDs affected by operations in this OpSet.
---@return table<uint64, boolean> #Set of Thing IDs.
function OpSet:get_thing_id_set()
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
function OpSet:get_player_index_set()
	local player_indices = {}
	local ops = self.by_index
	for i = 1, #ops do
		local op = ops[i]
		if op.player_index then player_indices[op.player_index] = true end
	end
	return player_indices
end

---Store this OpSet in global storage, if not already stored.
---@param player_index uint Player index of the player who is storing this OpSet.
function OpSet:store(player_index)
	if self.stored_id then return self.stored_id end
	local id = counters.next("opset")
	storage.stored_opsets[id] = self
	self.stored_id = id
	self.stored_player_index = player_index
	local tidset = self:get_thing_id_set()
	for tid, _ in pairs(tidset) do
		local thing = get_thing_by_id(tid)
		if thing then thing:undo_ref() end
	end
	return id
end

function OpSet:unstore()
	if not self.stored_id then return end
	storage.stored_opsets[self.stored_id] = nil
	local tidset = self:get_thing_id_set()
	for tid, _ in pairs(tidset) do
		local thing = get_thing_by_id(tid)
		if thing then thing:undo_unref() end
	end
	self.stored_id = nil
end

---@param opset_id int64?
---@return things.OpSet|nil #The stored OpSet, or nil if not found.
function lib.get_stored_opset(opset_id)
	return storage.stored_opsets[opset_id or ""]
end

return lib
