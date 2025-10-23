-- Create-thing op
local class = require("lib.core.class").class
local op_lib = require("control.op.op")
local ws_lib = require("lib.core.world-state")
local strace = require("lib.core.strace")
local thing_lib = require("control.thing")

local Op = op_lib.Op
local OpType = op_lib.OpType
local CREATE = OpType.CREATE
local get_world_state = ws_lib.get_world_state
local get_thing_by_id = thing_lib.get_by_id

local lib = {}

---@class things.CreateOp: things.Op
---@field public entity LuaEntity The entity created by this operation
---@field public name string Registration name of Thing to create.
---@field public tags? Tags Initial tags to set on the created Thing.
---@field public skip? true `true` if the creation is to be skipped due to invalidity
local CreateOp = class("things.CreateOp", op_lib.Op)
lib.CreateOp = CreateOp

---@param entity LuaEntity A *valid* entity.
---@param world_state? Core.WorldState The world state of the created entity. If omitted, it will be generated from the entity.
function CreateOp:new(entity, world_state)
	if not world_state then world_state = get_world_state(entity) end
	local obj = Op.new(self, CREATE, world_state) --[[@as things.CreateOp]]
	obj.entity = entity
	return obj
end

function CreateOp:dehydrate_for_undo()
	if self.tags and not self.skip then
		-- Redo operations will need the tags to recreate the Thing properly.
		self.entity = nil
		return true
	else
		-- Create ops without tags can be safely discarded.
		return false
	end
end

function CreateOp:resolve(frame)
	local entity = self.entity
	if
		not entity
		or not entity.valid
		or (entity.status == defines.entity_status.marked_for_deconstruction)
	then
		strace.debug(
			frame.debug_string,
			"CreateOp:resolve: entity is invalid or marked for deconstruction; skipping",
			self.key
		)
		self.skip = true
		return
	end

	local thing, was_created, err = thing_lib.make_thing(entity, self.name)
	if (not thing) or not was_created then
		strace.warn(
			frame.debug_string,
			"CreateOp:resolve: failed to thingify",
			self,
			was_created,
			err
		)
		self.skip = true
		return
	end

	self.thing_id = thing.id
	frame:mark_resolved(self.key, thing)
	strace.debug(
		frame.debug_string,
		"CreateOp:resolve: created Thing",
		thing.id,
		"for entity",
		entity,
		"at key",
		self.key
	)
end

---Fire initialization events at the reconcile phase which is latest possible
---time.
function CreateOp:reconcile(frame)
	local thing = get_thing_by_id(self.thing_id)
	if not thing then
		strace.warn(frame.debug_string, "CreateOp:reconcile: thing not found", self)
		return
	end

	frame:post_event("things.thing_initialized", thing)
end

return lib
