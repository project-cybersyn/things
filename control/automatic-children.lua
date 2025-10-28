-- Auto-children

local tlib = require("lib.core.table")
local thing_lib = require("control.thing")
local pos_lib = require("lib.core.math.pos")
local strace = require("lib.core.strace")
local reg_lib = require("control.registration")
local events = require("lib.core.event")

local get_thing_by_id = thing_lib.get_by_id
local EMPTY = tlib.EMPTY_STRICT

---Mutate the args to create a ghost entity.
---@param args LuaSurface.create_entity_param
local function to_ghost(args)
	local original_name = args.name
	args.name = "entity-ghost"
	-- TODO: support prototype values for name here?
	args.inner_name = original_name
	return args
end

---@param parent_thing things.Thing
---@param parent_entity LuaEntity
---@param index string|int
---@param def things.ThingRegistration.Child
---@param pos MapPosition
---@param orientation? Core.Orientation
local function create_child(
	parent_thing,
	parent_entity,
	index,
	def,
	pos,
	orientation,
	as_ghost
)
	if def.create then
		---@type LuaSurface.create_entity_param
		local create_args = tlib.assign({}, def.create)
		create_args.position = pos
		create_args.force = parent_entity.force
		create_args.raise_built = false
		create_args.create_build_effect_smoke = false
		create_args.preserve_ghosts_and_corpses = true
		create_args.quality = parent_entity.quality
		if as_ghost then to_ghost(create_args) end
		return parent_entity.surface.create_entity(create_args)
	else
		error("create_child: no create instructions")
	end
end

---@param entity LuaEntity
---@param name? string
---@param parent_thing things.Thing
---@param index string|int
---@param relative_pos? MapPosition
---@param relative_orientation? Core.Orientation
local function create_child_thing(
	entity,
	name,
	parent_thing,
	index,
	relative_pos,
	relative_orientation
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
---@param reg_children {[string|int]: things.ThingRegistration.Child}
local function check_children(parent_thing, reg_children)
	local parent_entity = parent_thing:get_entity()
	if not parent_entity then return end
	local parent_is_ghost = parent_thing.state == "ghost"
	local parent_is_real = parent_thing.state == "real"
	if (not parent_is_ghost) and not parent_is_real then
		strace.error(
			"check_children: Parent Thing ID",
			parent_thing.id,
			"is neither ghost nor real; shouldn't be here."
		)
		return
	end
	local did_work = false
	local children = parent_thing.children or EMPTY
	for index, def in pairs(reg_children) do
		local child_thing = get_thing_by_id(children[index])
		local child_pos, child_or = thing_lib.get_adjusted_pos_and_orientation(
			parent_thing,
			def.offset or { 0, 0 },
			def.orientation
		)

		local child_is_ghost = child_thing and child_thing.state == "ghost"
		local child_is_real = child_thing and child_thing.state == "real"
		local child_exists = child_is_ghost or child_is_real
		local child_lifecycle_type = def.lifecycle_type or "ghost-real"
		local child_always_real = child_lifecycle_type == "real-real"
		local child_void_real = child_lifecycle_type == "void-real"
		local child_ghost_real = child_lifecycle_type == "ghost-real"
		local child_should_be_ghost = parent_is_ghost and child_ghost_real
		local child_should_exist = parent_is_real or not child_void_real

		if (not child_thing) and child_should_exist then
			-- Create missing children
			local child_entity = create_child(
				parent_thing,
				parent_entity,
				index,
				def,
				child_pos --[[@as MapPosition]],
				child_or,
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
				did_work = true
			else
				strace.trace(
					"Automatic Children: Parent Thing ID",
					parent_thing.id,
					"Child index",
					index,
					"failed to create child entity."
				)
			end
		elseif child_thing and not child_exists and child_should_exist then
			-- Devoid voided children
			local child_entity = create_child(
				parent_thing,
				parent_entity,
				index,
				def,
				child_pos --[[@as MapPosition]],
				child_or,
				child_should_be_ghost
			)
			if child_entity then
				child_thing:devoid(child_entity)
				did_work = true
			else
				strace.trace(
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
			did_work = true
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
			did_work = true
		elseif
			parent_is_ghost
			and child_thing
			and child_is_real
			and child_should_be_ghost
		then
			-- Kill real children that should be ghosts
			child_thing:die()
			did_work = true
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
		if new_status == "destroyed" then return end
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
