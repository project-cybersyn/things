--- /things-doctor command - diagnose issues with Things.

local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")
local UNDO_TAG = constants.UNDO_TAG

local lib = {}

---@alias things.DoctorReport LocalisedString[]

---@return things.DoctorReport
local function report_new() return {} end

---@param report things.DoctorReport
---@param message LocalisedString
local function report_append(report, message) table.insert(report, message) end

local function doctor_demographics(report)
	-- Basic storage
	local n_things = table_size(storage.things)
	local n_things_un = table_size(storage.things_by_unit_number)

	report_append(report, "[font=default-bold]Things Lifecycle:[/font]")

	report_append(
		report,
		string.format(
			"Total things: %d (%d in unit_number map)",
			n_things,
			n_things_un
		)
	)

	-- Things by lifecycle state
	---@type {[string]: table<things.Thing, true>}
	local by_state = { real = {}, ghost = {}, void = {}, destroyed = {} }
	for _, thing in pairs(storage.things) do
		local state = thing.state or "UNKNOWN"
		by_state[state] = (by_state[state] or {})
		by_state[state][thing] = true
	end
	local cat_tbl = { "  By lifecycle state:" }
	for state, things in pairs(by_state) do
		cat_tbl[#cat_tbl + 1] =
			string.format("    %s: %d", state, table_size(things))
	end
	report_append(report, table.concat(cat_tbl))

	local n_real = table_size(by_state.real)
	local n_ghost = table_size(by_state.ghost)
	if n_real + n_ghost ~= n_things_un then
		report_append(
			report,
			string.format(
				"[color=red]Count of things in unit_number map (%d) does not match real + ghost (%d + %d = %d)![/color]",
				n_things_un,
				n_real,
				n_ghost,
				n_real + n_ghost
			)
		)
	end

	-- Real things should have real entities
	for thing in pairs(by_state.real) do
		if not thing.entity or not thing.entity.valid then
			report_append(
				report,
				string.format(
					"[color=red]Thing ID %d is real but has no valid entity![/color]",
					thing.id
				)
			)
		end
	end

	-- Ghost things should have ghost entities
	for thing in pairs(by_state.ghost) do
		if
			not thing.entity
			or not thing.entity.valid
			or thing.entity.type ~= "entity-ghost"
		then
			report_append(
				report,
				string.format(
					"[color=red]Thing ID %d is a ghost but has no valid ghost entity![/color]",
					thing.id
				)
			)
		end
	end

	-- Voided things should have no entities
	for thing in pairs(by_state.void) do
		if thing.entity and thing.entity.valid then
			report_append(
				report,
				string.format(
					"[color=red]Thing ID %d is void but has a valid entity![/color]",
					thing.id
				)
			)
		end
	end
end

---@alias things.DoctorReachabilityType "entity" | "undo" | "child"

---@param report things.DoctorReport
local function doctor_reachability(report)
	---@type {[int64]: true}
	local unreachable_things = tlib.t_map_t(
		storage.things,
		function(id) return id, true end
	) --[[@as {[int64]: true} ]]
	---@type {[int64]: things.DoctorReachabilityType}
	local reachable_things = {}

	local unreachable_opsets = tlib.t_map_t(
		storage.stored_opsets,
		function(id) return id, true end
	) --[[@as {[int64]: true} ]]
	---@type {[int64]: true}
	local reachable_opsets = {}

	-- Things that are real or ghost and have valid entities are reachable via their entities
	for _, thing in pairs(storage.things) do
		if
			(thing.state == "real" or thing.state == "ghost")
			and thing.entity
			and thing.entity.valid
		then
			reachable_things[thing.id] = "entity"
			unreachable_things[thing.id] = nil
		end
	end

	-- For each player, every opset on that player's undo stack is reachable
	for _, player in pairs(game.players) do
		local stack = player.undo_redo_stack
		for i = 1, stack.get_undo_item_count() do
			local actions = stack.get_undo_item(i)
			for _, action in pairs(actions) do
				local undo_tag = action.tags and action.tags[UNDO_TAG]
				if undo_tag then
					---@diagnostic disable-next-line: param-type-mismatch
					for _, opset_id in pairs(undo_tag) do
						reachable_opsets[opset_id] = true
						unreachable_opsets[opset_id] = nil
					end
				end
			end
		end
		for i = 1, stack.get_redo_item_count() do
			local actions = stack.get_redo_item(i)
			for _, action in pairs(actions) do
				local undo_tag = action.tags and action.tags[UNDO_TAG]
				if undo_tag then
					---@diagnostic disable-next-line: param-type-mismatch
					for _, opset_id in pairs(undo_tag) do
						reachable_opsets[opset_id] = true
						unreachable_opsets[opset_id] = nil
					end
				end
			end
		end
	end

	-- For each reachable opset, all its Things are reachable.
	for opset_id in pairs(reachable_opsets) do
		local opset = storage.stored_opsets[opset_id]
		if opset then
			local thing_ids = opset:get_thing_id_set()
			for thing_id in pairs(thing_ids) do
				if not reachable_things[thing_id] then
					reachable_things[thing_id] = "undo"
					unreachable_things[thing_id] = nil
				end
			end
		end
	end

	-- For each thing that's a child, if its root-level parent is reachable, it is reachable.
	for thing_id, thing in pairs(storage.things) do
		if reachable_things[thing_id] then goto continue end
		if thing.parent then
			---@type int64?
			local parent_thing_id = thing.parent[1]
			while parent_thing_id do
				if reachable_things[parent_thing_id] then
					reachable_things[thing_id] = "child"
					unreachable_things[thing_id] = nil
					break
				end
				local parent_thing = storage.things[parent_thing_id]
				if parent_thing and parent_thing.parent then
					parent_thing_id = parent_thing.parent[1]
				else
					parent_thing_id = nil
				end
			end
		end
		::continue::
	end

	-- Report general reachability statistics.
	local n_unreachable_things = table_size(unreachable_things)
	local n_reachable_things = table_size(reachable_things)
	report_append(
		report,
		string.format(
			"Reachability: %d reachable things, %d unreachable things; %d reachable opsets, %d unreachable opsets.",
			n_reachable_things,
			n_unreachable_things,
			table_size(reachable_opsets),
			table_size(unreachable_opsets)
		)
	)

	-- Report counts for each type of reachability
	local cat_tbl = { "  Reachable things by reachable type:" }
	local by_type = tlib.t_reduce(
		reachable_things,
		{},
		function(type_tbl, thing_id, type)
			type_tbl[type] = (type_tbl[type] or 0) + 1
			return type_tbl
		end
	)
	for type, count in pairs(by_type) do
		cat_tbl[#cat_tbl + 1] = string.format("    %s: %d", type, count)
	end
	report_append(report, table.concat(cat_tbl))
end

---@param report things.DoctorReport
local function dump_report(report)
	for _, message in ipairs(report) do
		game.print(
			message,
			{ skip = defines.print_skip.never, sound = defines.print_sound.never }
		)
		log(message)
	end
end

commands.add_command(
	"things-doctor",
	{ "things-commands.doctor-command-help" },
	function()
		local report = report_new()

		doctor_demographics(report)
		doctor_reachability(report)

		dump_report(report)
	end
)

return lib
