-- Auto-children

local tlib = require("lib.core.table")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")
local strace = require("lib.core.strace")
local reg_lib = require("control.registration")
local events = require("lib.core.event")
local types = require("client.types")

---@type things.Storage
storage = storage --[[@as things.Storage]]

local pairs = pairs
local get_thing_by_id = thing_lib.get_by_id
local EMPTY = tlib.EMPTY_STRICT
local RAISE_DESTROY = { raise_destroy = true }
local RAISE_REVIVE = { raise_revive = true }
local LifecycleType = types.LifecycleType
local VOID_GHOST_REAL = LifecycleType.VOID_GHOST_REAL
local VOID_REAL_REAL = LifecycleType.VOID_REAL_REAL
local VOID_VOID_REAL = LifecycleType.VOID_VOID_REAL
local DESTROYED_DESTROYED_REAL = LifecycleType.DESTROYED_DESTROYED_REAL
local DESTROYED_REAL_REAL = LifecycleType.DESTROYED_REAL_REAL
local ZERO = { 0, 0 }

---@class things.UnthingChildInfo : things.ParentRelationshipInfo
---@field public [6] LuaEntity? The entity of the unthing child, if it exists.

---@param unit_number UnitNumber?
---@return things.UnthingChildInfo?
function get_unthing_child(unit_number)
	if not unit_number then return nil end
	return storage.unthing_children[unit_number]
end

---@param unit_number UnitNumber?
---@param deparent boolean? If true, remove the child from its parent Thing's children list.
---@param destroy_entity boolean? If true, destroy the entity of the unthing child, if it exists.
function remove_unthing_child(unit_number, deparent, destroy_entity)
	if not unit_number then return false end
	local info = storage.unthing_children[unit_number]
	if not info then return false end
	if deparent then
		local parent_id, parent_index = info[1], info[2]
		local parent_thing = storage.things[parent_id]
		if parent_thing then parent_thing:remove_child(parent_index) end
	end
	storage.unthing_children[unit_number] = nil
	if destroy_entity then
		local entity = info[6]
		if entity and entity.valid then
			strace.trace(
				"Destroying unthing child entity with unit number",
				unit_number
			)
			entity.destroy(RAISE_DESTROY)
		end
	end
	return true
end

---@param entity LuaEntity?
---@param parent_thing things.Thing
---@param index string
---@param relative_pos? MapPosition
---@param relative_orientation? Core.Orientation
---@param lifecycle? things.LifecycleType
function create_unthing_child(
	entity,
	parent_thing,
	index,
	relative_pos,
	relative_orientation,
	lifecycle
)
	if not entity or not entity.valid then return nil end
	if not parent_thing then return nil end
	local un = entity.unit_number
	if (not un) or storage.unthing_children[un] then return nil end
	storage.unthing_children[un] = {
		parent_thing.id,
		index,
		relative_pos,
		relative_orientation,
		lifecycle,
		entity,
	}
	script.register_on_object_destroyed(entity)
	return un
end

---Mutate the args to create a ghost entity.
---@param args Partial<LuaSurface.create_entity_param>
local function to_ghost(args)
	local original_name = args.name
	args.name = "entity-ghost"
	-- TODO: support prototype values for name here?
	args.inner_name = original_name --[[@as string]]
	return args
end

---@param parent_entity LuaEntity
---@param def things.ThingRegistration.Child
---@param pos MapPosition
---@param as_ghost boolean?
local function create_child_entity(parent_entity, def, pos, as_ghost)
	if def.create then
		---@type Partial<LuaSurface.create_entity_param>
		local create_args = tlib.assign({}, def.create)
		create_args.position = pos
		create_args.force = parent_entity.force
		create_args.raise_built = false
		create_args.create_build_effect_smoke = false
		create_args.preserve_ghosts_and_corpses = true
		create_args.quality = parent_entity.quality
		if as_ghost then to_ghost(create_args) end
		return parent_entity.surface.create_entity(
			create_args --[[@as LuaSurface.create_entity_param]]
		)
	else
		error("create_child: no create instructions")
	end
end

---@param entity LuaEntity
---@param name? string
---@param parent_thing things.Thing
---@param index string
---@param relative_pos? MapPosition
---@param relative_orientation? Core.Orientation
---@param lifecycle? things.LifecycleType
local function create_child_thing(
	entity,
	name,
	parent_thing,
	index,
	relative_pos,
	relative_orientation,
	lifecycle
)
	local is_ghost = entity.type == "entity-ghost"
	if not name then name = is_ghost and entity.ghost_name or entity.name end
	local child_thing, was_created, err = thing_lib.make_thing(entity, name)
	strace.debug(
		"Automatic Children: Created child Thing ID",
		child_thing and child_thing.id or "N/A",
		is_ghost and "(ghost)" or "",
		"for parent Thing ID",
		parent_thing.id,
		"at index",
		index,
		err
	)
	if child_thing and was_created then
		-- Mindful of event ordering here: child must init after parent is added.
		local child_was_added = parent_thing:add_child(
			index,
			child_thing,
			relative_pos,
			relative_orientation,
			lifecycle,
			true
		)
		child_thing:initialize()
		if child_was_added then
			parent_thing:raise_event(
				"things.thing_children_changed",
				parent_thing,
				child_thing,
				nil
			)
		end
	end
end

---@param parent_thing things.Thing
---@param parent_entity LuaEntity
---@param child_thing_id things.Id?
---@param index string
---@param def things.ThingRegistration.Child
---@param parent_is_ghost boolean
---@param parent_is_real boolean
---@return boolean
local function check_thing_child(
	parent_thing,
	parent_entity,
	child_thing_id,
	index,
	def,
	parent_is_ghost,
	parent_is_real
)
	local child_thing = get_thing_by_id(child_thing_id)
	local child_pos, child_or = thing_lib.get_adjusted_pos_and_orientation(
		parent_thing:get_entity(),
		parent_thing:get_orientation(),
		def.offset or ZERO,
		def.orientation
	)

	local child_is_ghost = child_thing and child_thing.state == "ghost"
	local child_is_real = child_thing and child_thing.state == "real"
	local child_exists = child_is_ghost or child_is_real
	---@diagnostic disable-next-line: undefined-field
	local child_lifecycle_type = def._lifecycle or VOID_GHOST_REAL
	local child_always_real = child_lifecycle_type == VOID_REAL_REAL
	local child_void_real = child_lifecycle_type == VOID_VOID_REAL
	local child_ghost_real = child_lifecycle_type == VOID_GHOST_REAL
	local child_should_be_ghost = parent_is_ghost and child_ghost_real
	local child_should_exist = parent_is_real or not child_void_real

	if (not child_thing) and child_should_exist then
		-- Create missing children
		local child_entity = create_child_entity(
			parent_entity,
			def,
			child_pos --[[@as MapPosition]],
			child_should_be_ghost
		)
		if child_entity then
			create_child_thing(
				child_entity,
				nil,
				parent_thing,
				index,
				def.offset,
				def.orientation
			)
			return true
		else
			strace.warn(
				"Automatic Children: Parent Thing ID",
				parent_thing.id,
				"Child index",
				index,
				"failed to create child entity."
			)
		end
	elseif child_thing and not child_exists and child_should_exist then
		-- Devoid voided children
		local child_entity = create_child_entity(
			parent_entity,
			def,
			child_pos --[[@as MapPosition]],
			child_should_be_ghost
		)
		if child_entity then
			child_thing:devoid(child_entity)
			return true
		else
			strace.warn(
				"Automatic Children: Parent Thing ID",
				parent_thing.id,
				"Child index",
				index,
				"failed to re-create voided child entity."
			)
		end
	elseif child_thing and child_exists and not child_should_exist then
		-- Void existing children that shouldn't exist
		child_thing:void()
		return true
	elseif parent_is_real and child_thing and child_is_ghost then
		-- Revive ghost children
		strace.trace(
			"Automatic Children: Parent Thing ID",
			parent_thing.id,
			"Child index",
			index,
			"auto-reviving ghost."
		)
		child_thing:revive()
		return true
	elseif
		parent_is_ghost
		and child_thing
		and child_is_real
		and child_should_be_ghost
	then
		-- Kill real children that should be ghosts
		child_thing:die()
		return true
	end
	return false
end

---@param parent_thing things.Thing
---@param parent_entity LuaEntity
---@param child_unit_number UnitNumber?
---@param index string
---@param def things.ThingRegistration.Child
---@param parent_is_ghost boolean
---@param parent_is_real boolean
---@return boolean
local function check_unthing_child(
	parent_thing,
	parent_entity,
	child_unit_number,
	index,
	def,
	parent_is_ghost,
	parent_is_real
)
	local parent_child_info = child_unit_number
		and storage.unthing_children[child_unit_number]

	local child_entity = parent_child_info and parent_child_info[6]
	if child_entity and not child_entity.valid then
		strace.warn(
			"Automatic Children: Referential integrity warning: Parent Thing ID",
			parent_thing.id,
			"Child index",
			index,
			"had an invalid entity. Removing child from unthing_children."
		)
		remove_unthing_child(child_unit_number, true, false)
		child_entity = nil
		parent_child_info = nil
	end

	local child_pos, child_or = thing_lib.get_adjusted_pos_and_orientation(
		parent_thing:get_entity(),
		parent_thing:get_orientation(),
		def.offset or ZERO,
		def.orientation
	)

	local child_exists = not not child_entity
	local child_is_ghost = child_entity and child_entity.type == "entity-ghost"
	local child_is_real = child_entity and not child_is_ghost
	---@diagnostic disable-next-line: undefined-field
	local child_lifecycle_type = def._lifecycle or DESTROYED_DESTROYED_REAL
	local child_always_real = child_lifecycle_type == DESTROYED_REAL_REAL
	local child_void_real = child_lifecycle_type == DESTROYED_DESTROYED_REAL
	local child_should_exist = parent_is_real or not child_void_real

	if (not child_entity) and child_should_exist then
		-- Create missing children
		child_entity =
			create_child_entity(parent_entity, def, child_pos --[[@as MapPosition]])
		if child_entity then
			parent_thing:add_child(
				index,
				child_entity,
				def.offset,
				def.orientation,
				child_lifecycle_type,
				false
			)
			return true
		else
			strace.warn(
				"Automatic Children: Parent Thing ID",
				parent_thing.id,
				"Child index",
				index,
				"failed to create child entity."
			)
		end
	elseif child_entity and not child_should_exist then
		remove_unthing_child(child_entity.unit_number, true, true)
		return true
	elseif parent_is_real and child_entity and child_is_ghost then
		-- Revive ghost children
		strace.trace(
			"Automatic Children: Parent Thing ID",
			parent_thing.id,
			"Child index",
			index,
			"auto-reviving ghost."
		)
		child_entity.revive(RAISE_REVIVE)
		return true
	end
	return false
end

---@param parent_thing things.Thing
---@param reg_children {[string]: things.ThingRegistration.Child}
local function check_children(parent_thing, reg_children)
	local parent_entity = parent_thing:get_entity()
	if not parent_entity then return end
	local parent_is_ghost = parent_thing.state == "ghost"
	local parent_is_real = parent_thing.state == "real"
	if (not parent_is_ghost) and not parent_is_real then
		error(
			"LOGIC ERROR: `check_children` on a Thing that is neither ghost nor real: Thing ID "
				.. parent_thing.id
		)
		return
	end
	local did_work = false
	local children = parent_thing.children or EMPTY
	-- For each registered child
	for index, def in pairs(reg_children) do
		---@diagnostic disable-next-line: undefined-field
		local def_is_thing = not def._unthing
		local child = children[index]
		if child then
			-- Check for mismatched thingness
			local child_is_thing = type(child) == "number"
			if child_is_thing and not def_is_thing then
				-- Child is a Thing, but definition says it should be an Unthing.
				-- Remove the child Thing.
				local child_thing = get_thing_by_id(child)
				if child_thing then child_thing:destroy() end
				child = nil
			elseif not child_is_thing and def_is_thing then
				remove_unthing_child(child[1], true, true)
				child = nil
			end
		end

		if def_is_thing then
			---@cast child things.Id?
			if
				check_thing_child(
					parent_thing,
					parent_entity,
					child,
					index,
					def,
					parent_is_ghost,
					parent_is_real
				)
			then
				did_work = true
			end
		else
			if
				check_unthing_child(
					parent_thing,
					parent_entity,
					child and child[1],
					index,
					def,
					parent_is_ghost,
					parent_is_real
				)
			then
				did_work = true
			end
		end
	end
	if did_work then
		parent_thing:raise_event("things.thing_children_normalized", parent_thing)
	end
end

events.bind(
	"things.thing_initialized",
	---@param thing things.Thing
	function(thing)
		local reg = thing:get_registration()
		if reg and reg.children then check_children(thing, reg.children) end
	end
)

events.bind(
	"things.thing_status",
	---@param thing things.Thing
	function(thing, old_status)
		local new_status = thing.state
		if new_status == "destroyed" then
			-- Destruction of destroyed Thing children is handled in Thing core.
			return
		end
		if
			old_status == "void"
			or new_status == "ghost"
			or new_status == "real"
		then
			local reg = thing:get_registration()
			if reg and reg.children then check_children(thing, reg.children) end
		end
	end
)
