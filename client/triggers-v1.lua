local rcall = remote and remote.call --[[@as (fun(iface: string, method: string, ...: Any): Any...) ]]
local comb = require("client.combinators-v1")

local create_invisible = comb.create_invisible
local create_invisible_raw = comb.create_invisible_raw

---@class things.client.TriggersV1Lib
local lib = {}

---@class (exact) things.TriggerInfo
---@field public trigger_id things.Id The unique identifier for the trigger
---@field public entity LuaEntity The entity controlling the trigger
---@field public thing_id things.Id The thing ID to notify when the trigger takes place
---@field public fired_tick? int64 The tick at which the trigger was last fired. This is updated each time the trigger fires.
---@field public trigger_after? int64 Don't fire again until after this tick. If `nil`, the trigger can fire every tick.
---@field public debounce_ticks uint32? The number of ticks to wait before allowing the trigger to fire again. If `nil`, the trigger will fire every tick.
---@field public trigger_data Any? Additional data to include in the event when the trigger fires. This can be used to pass custom information to the event handler.

---@type LandMineBlueprintControlBehavior
local mine_control_behavior = {
	input_networks = { red = true, green = true },
	circuit_enabled = true,
	circuit_condition = {
		first_signal = {
			type = "virtual",
			name = "things-signal-trigger",
		},
		constant = 0,
		comparator = "!=",
	},
}

---@param parent_entity LuaEntity
---@param control_behavior LandMineBlueprintControlBehavior?
local function create_trigger_mine(parent_entity, control_behavior)
	local _, entity =
		create_invisible(parent_entity.surface, "land-mine", false, {
			position = parent_entity.position,
			force = parent_entity.force,
			control_behavior = control_behavior or mine_control_behavior,
		})
	return entity
end

---@param trigger_mine_prototype string
---@param parent_entity LuaEntity
---@param control_behavior LandMineBlueprintControlBehavior?
---@return LuaEntity?
local function create_custom_trigger_mine(
	trigger_mine_prototype,
	parent_entity,
	control_behavior
)
	local entity =
		create_invisible_raw(parent_entity.surface, trigger_mine_prototype, {
			position = parent_entity.position,
			force = parent_entity.force,
			control_behavior = control_behavior or mine_control_behavior,
		})
	return entity
end

local function raw_create_trigger(
	parent_thing_id,
	child_index,
	entity,
	control_behavior,
	debounce_ticks
)
	local mine = create_trigger_mine(entity, control_behavior)
	if not mine then return end
	local un = mine.unit_number --[[@as UnitNumber ]]
	rcall(
		"things-ca-v1",
		"add_unthing_child",
		parent_thing_id,
		child_index or "_trigger",
		mine,
		{ 0, 0 }
	)
	rcall("things-ca-v1", "set_trigger_info", un, {
		trigger_id = un,
		entity = mine,
		thing_id = parent_thing_id,
		debounce_ticks = debounce_ticks,
	})
	return un, mine
end

---Create a trigger object and attach it to a parent Thing. When the object is triggered, the custom event "on_trigger" will fire for the parent Thing.
---@param parent_thing_id things.Id The thing id of the parent thing to attach the trigger to.
---@param child_index string? The key to use for the trigger child entity. If `nil`, the default key "_trigger" will be used.
---@param debounce_ticks? uint? The number of ticks to wait before allowing the trigger to fire again. If `nil`, the trigger can fire every tick.
---@param control_behavior? LandMineBlueprintControlBehavior The control behavior to use for the trigger mine. If not given, a default control behavior will be used that triggers on the "things-signal-trigger" hidden virtual signal.
---@return things.Id? trigger_id The unique identifier for the created trigger. Returns `nil` if the parent Thing does not exist or the trigger could not be created.
---@return LuaEntity? trigger_entity The entity controlling the trigger. Returns `nil` if the parent Thing does not exist or the trigger could not be created.
local function create_trigger(
	parent_thing_id,
	child_index,
	debounce_ticks,
	control_behavior
)
	local thing = rcall("things-ca-v1", "get", parent_thing_id)
	if not thing then return end
	local entity = thing.entity
	if not entity then return end
	return raw_create_trigger(
		parent_thing_id,
		child_index,
		entity,
		control_behavior,
		debounce_ticks
	)
end
lib.create_trigger = create_trigger

---Create a custom trigger object and attach it to a parent Thing. No event management is done; you must intercept the associated event you provided with `get_trigger_mine_prototype` and handle it yourself using `check_custom_trigger` to determine if the trigger should fire.
---@param trigger_mine_prototype string The name of the trigger mine prototype to create.
---@param parent_thing_id things.Id The thing id of the parent thing to attach the trigger to.
---@param child_index string? The key to use for the trigger child entity. If `nil`, the default key "_trigger" will be used.
---@param control_behavior? LandMineBlueprintControlBehavior The control behavior to use for the trigger mine. If not given, a default control behavior will be used that triggers on the "things-signal-trigger" hidden virtual signal.
---@return things.Id? trigger_id An ID for the trigger. This is just the `unit_number` of the trigger entity. Returns `nil` if the trigger could not be created.
---@return LuaEntity? trigger_entity The entity controlling the trigger. Returns `nil` if trigger could not be created.
local function create_custom_trigger(
	trigger_mine_prototype,
	parent_thing_id,
	child_index,
	control_behavior
)
	local thing = rcall("things-ca-v1", "get", parent_thing_id)
	if not thing then return end
	local entity = thing.entity
	if not entity then return end
	local mine =
		create_custom_trigger_mine(trigger_mine_prototype, entity, control_behavior)
	if not mine then return end
	local un = mine.unit_number --[[@as UnitNumber ]]
	rcall(
		"things-ca-v1",
		"add_unthing_child",
		parent_thing_id,
		child_index or "_trigger",
		mine,
		{ 0, 0 }
	)
	rcall("things-ca-v1", "set_trigger_info", un, {
		trigger_id = un,
		entity = mine,
		thing_id = parent_thing_id,
	})
	return un, mine
end
lib.create_custom_trigger = create_custom_trigger

---Arm or disarm a previously created trigger object. Disarming trigger objects when they are not needed will *considerably* improve performance.
---@param trigger_id things.Id? The unique identifier for the trigger to arm or disarm. This is the value returned by `create_trigger`.
---@param is_armed boolean Whether to arm (`true`) or disarm (`false`) the trigger.
---@return boolean success Returns `true` if the trigger was successfully armed or disarmed, or `false` if the trigger does not exist or could not be modified.
local function arm_trigger(trigger_id, is_armed)
	if not trigger_id then return false end
	return rcall("things-ca-v1", "set_trigger_armed", trigger_id, is_armed) --[[@as boolean ]]
end
lib.arm_trigger = arm_trigger

---Check if a trigger previously created by `create_custom_trigger` should fire. This handles debouncing and other edge cases. You must call this function in your event handler for the trigger's custom event.
---@param ev EventData.on_script_trigger_effect The event data from the trigger event fired by the custom trigger.
---@return things.Id? triggered_thing_id Returns the thing ID of the parent Thing that owns the trigger if the trigger should fire, or `nil` if it should not fire.
---@return things.Id? trigger_id Returns the unique identifier for the trigger that fired, or `nil` if it should not fire.
local function handle_custom_trigger_event(ev)
	local trigger = ev.source_entity
	if not trigger then return nil end
	local trigger_id = trigger.unit_number --[[@as UnitNumber]]
	if not trigger_id then return nil end
	local parent = rcall("things-ca-v1", "check_trigger", trigger_id) --[[@as things.Id? ]]
	return parent, trigger_id
end
lib.handle_custom_trigger_event = handle_custom_trigger_event

--------------------------------------------------------------------------------
-- CIRCUIT CHANGE DETECTION TRIGGERS
--------------------------------------------------------------------------------

---@type DeciderCombinatorBlueprintControlBehavior
local red_latch_control_behavior = {
	decider_conditions = {
		conditions = {
			{
				first_signal = {
					type = "virtual",
					name = "signal-each",
				},
				second_signal = {
					type = "virtual",
					name = "signal-each",
				},
				comparator = "=",
				first_signal_networks = {
					red = true,
					green = false,
				},
				second_signal_networks = {
					red = false,
					green = true,
				},
			},
			{
				first_signal = {
					type = "virtual",
					name = "things-signal-trigger",
				},
				comparator = "!=",
			},
		},
		outputs = {
			{
				signal = {
					type = "virtual",
					name = "signal-each",
				},
				networks = {
					red = true,
					green = false,
				},
			},
		},
		else_outputs = {
			{
				signal = {
					type = "virtual",
					name = "signal-each",
				},
				networks = {
					red = true,
					green = false,
				},
			},
			{
				signal = {
					type = "virtual",
					name = "things-signal-trigger",
				},
				copy_count_from_input = false,
			},
		},
	},
}

---@type DeciderCombinatorBlueprintControlBehavior
local green_latch_control_behavior = {
	decider_conditions = {
		conditions = {
			{
				first_signal = {
					type = "virtual",
					name = "signal-each",
				},
				second_signal = {
					type = "virtual",
					name = "signal-each",
				},
				comparator = "=",
				first_signal_networks = {
					red = false,
					green = true,
				},
				second_signal_networks = {
					red = true,
					green = false,
				},
			},
			{
				first_signal = {
					type = "virtual",
					name = "things-signal-trigger",
				},
				comparator = "!=",
			},
		},
		outputs = {
			{
				signal = {
					type = "virtual",
					name = "signal-each",
				},
				networks = {
					red = false,
					green = true,
				},
			},
		},
		else_outputs = {
			{
				signal = {
					type = "virtual",
					name = "signal-each",
				},
				networks = {
					red = false,
					green = true,
				},
			},
			{
				signal = {
					type = "virtual",
					name = "things-signal-trigger",
				},
				copy_count_from_input = false,
			},
		},
	},
}

local CIRCUIT_RED = defines.wire_connector_id.circuit_red
local OUTPUT_RED = defines.wire_connector_id.combinator_output_red
local INPUT_RED = defines.wire_connector_id.combinator_input_red
local CIRCUIT_GREEN = defines.wire_connector_id.circuit_green
local OUTPUT_GREEN = defines.wire_connector_id.combinator_output_green
local INPUT_GREEN = defines.wire_connector_id.combinator_input_green
local SCRIPT = defines.wire_origin.script

---@param parent_thing_id things.Id
---@param parent_entity LuaEntity
---@param prefix string
---@param mine LuaEntity
---@param red_circuit LuaWireConnector?
---@param green_circuit LuaWireConnector?
---@return boolean success
---@return LuaEntity? red_latch
---@return LuaEntity? green_latch
local function create_edge_detector_combs(
	parent_thing_id,
	parent_entity,
	prefix,
	mine,
	red_circuit,
	green_circuit
)
	local red_latch
	if red_circuit then
		_, red_latch =
			create_invisible(parent_entity.surface, "decider-combinator", false, {
				position = parent_entity.position,
				force = parent_entity.force,
				control_behavior = red_latch_control_behavior,
			})
		if not red_latch then return false end

		-- Comb red out -> mine red in
		local mine_red_input = mine.get_wire_connector(CIRCUIT_RED, true) --[[@as LuaWireConnector]]
		local comb_red_output = red_latch.get_wire_connector(OUTPUT_RED, true) --[[@as LuaWireConnector]]
		comb_red_output.connect_to(mine_red_input, false, SCRIPT)

		-- Comb green out -> comb green in
		local comb_green_input = red_latch.get_wire_connector(INPUT_GREEN, true) --[[@as LuaWireConnector]]
		local comb_green_output = red_latch.get_wire_connector(OUTPUT_GREEN, true) --[[@as LuaWireConnector]]
		comb_green_output.connect_to(comb_green_input, false, SCRIPT)

		-- Circuit red -> comb red in
		local comb_red_input = red_latch.get_wire_connector(INPUT_RED, true) --[[@as LuaWireConnector]]
		red_circuit.connect_to(comb_red_input, false, SCRIPT)

		rcall(
			"things-ca-v1",
			"add_unthing_child",
			parent_thing_id,
			prefix .. "_red_latch",
			red_latch,
			{ 0, 0 }
		)
	end

	local green_latch
	if green_circuit then
		_, green_latch =
			create_invisible(parent_entity.surface, "decider-combinator", false, {
				position = parent_entity.position,
				force = parent_entity.force,
				control_behavior = green_latch_control_behavior,
			})
		if not green_latch then
			if red_latch then red_latch.destroy() end
			return false
		end

		-- Comb green out -> mine green in
		local mine_green_input = mine.get_wire_connector(CIRCUIT_GREEN, true) --[[@as LuaWireConnector]]
		local comb_green_output = green_latch.get_wire_connector(OUTPUT_GREEN, true) --[[@as LuaWireConnector]]
		comb_green_output.connect_to(mine_green_input, false, SCRIPT)

		-- Comb red out -> comb red in
		local comb_red_input = green_latch.get_wire_connector(INPUT_RED, true) --[[@as LuaWireConnector]]
		local comb_red_output = green_latch.get_wire_connector(OUTPUT_RED, true) --[[@as LuaWireConnector]]
		comb_red_output.connect_to(comb_red_input, false, SCRIPT)

		-- Circuit green -> comb green in
		local comb_green_input = green_latch.get_wire_connector(INPUT_GREEN, true) --[[@as LuaWireConnector]]
		green_circuit.connect_to(comb_green_input, false, SCRIPT)

		rcall(
			"things-ca-v1",
			"add_unthing_child",
			parent_thing_id,
			prefix .. "_green_latch",
			green_latch,
			{ 0, 0 }
		)
	end
	return true, red_latch, green_latch
end

---Create a specialized trigger designed to detect changes in circuit inputs. You must provide a red and/or green wire connector to be monitored for changes. The parent Thing will receive trigger events whenever the monitored circuit inputs change.
---@param parent_thing_id things.Id The thing id of the parent thing to attach the circuit change detector to.
---@param prefix string A prefix to use for the names of the invisible combinators created.
---@param red_circuit LuaWireConnector? The red wire connector to monitor for changes. If `nil`, no red wire monitoring will be performed.
---@param green_circuit LuaWireConnector? The green wire connector to monitor for changes. If `nil`, no green wire monitoring will be performed.
---@return things.Id? trigger_id The unique identifier for the created trigger. Returns `nil` if the trigger could not be created.
local function create_circuit_change_detector(
	parent_thing_id,
	prefix,
	red_circuit,
	green_circuit
)
	if (not red_circuit) and not green_circuit then return end
	local thing = rcall("things-ca-v1", "get", parent_thing_id)
	if not thing then return end
	local parent_entity = thing.entity
	if not parent_entity then return end
	local trigger_id, mine =
		raw_create_trigger(parent_thing_id, prefix .. "_trigger", parent_entity)
	if not mine then return nil end

	local success = create_edge_detector_combs(
		parent_thing_id,
		parent_entity,
		prefix,
		mine,
		red_circuit,
		green_circuit
	)
	if not success then
		mine.destroy()
		return nil
	end

	return trigger_id
end
lib.create_circuit_change_detector = create_circuit_change_detector

---Create a custom trigger designed to detect changes in circuit inputs. You must provide a custom trigger prototype and handle the trigger events yourself with the help of `check_custom_trigger`.
---@param trigger_mine_prototype string The name of the trigger mine prototype to create.
---@param parent_thing_id things.Id The thing id of the parent thing to attach the circuit change detector to.
---@param prefix string A prefix to use for the names of the invisible children created.
---@param red_circuit LuaWireConnector? The red wire connector to monitor for changes. If `nil`, no red wire monitoring will be performed.
---@param green_circuit LuaWireConnector? The green wire connector to monitor for changes. If `nil`, no green wire monitoring will be performed.
---@return things.Id? trigger_id The unique identifier for the created trigger. Returns `nil` if the trigger could not be created.
---@return LuaEntity? trigger_entity The entity controlling the trigger. Returns `nil` if the trigger could not be created.
local function create_custom_circuit_change_detector(
	trigger_mine_prototype,
	parent_thing_id,
	prefix,
	red_circuit,
	green_circuit
)
	if (not red_circuit) and not green_circuit then return end
	local thing = rcall("things-ca-v1", "get", parent_thing_id)
	if not thing then return end
	local parent_entity = thing.entity
	if not parent_entity then return end
	local trigger_id, mine = create_custom_trigger(
		trigger_mine_prototype,
		parent_thing_id,
		prefix .. "_trigger"
	)
	if not mine then return nil end

	local success = create_edge_detector_combs(
		parent_thing_id,
		parent_entity,
		prefix,
		mine,
		red_circuit,
		green_circuit
	)
	if not success then
		mine.destroy()
		return nil
	end

	return trigger_id, mine
end
lib.create_custom_circuit_change_detector =
	create_custom_circuit_change_detector

---Destroy a previously created circuit change detector. Note that it is rarely necessary to call this function, as destroying the parent Thing will automatically destroy all of its children, including the circuit change detector.
---@param parent_thing_id things.Id The thing id of the parent thing to detach the circuit change detector from.
---@param prefix string The prefix used with `create_circuit_change_detector` when the circuit change detector was created.
local function destroy_circuit_change_detector(parent_thing_id, prefix)
	rcall(
		"things-ca-v1",
		"remove_child",
		parent_thing_id,
		prefix .. "_trigger",
		true
	)
	rcall(
		"things-ca-v1",
		"remove_child",
		parent_thing_id,
		prefix .. "_red_latch",
		true
	)
	rcall(
		"things-ca-v1",
		"remove_child",
		parent_thing_id,
		prefix .. "_green_latch",
		true
	)
end
lib.destroy_circuit_change_detector = destroy_circuit_change_detector

return lib
