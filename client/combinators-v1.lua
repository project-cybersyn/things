-- Combinator module, client side

local tlib = require("lib.core.table")

local rcall = remote and remote.call --[[@as (fun(iface: string, method: string, ...: Any): Any...) ]]

---@class things.client.CombinatorsV1Lib
local lib = {}

local TINY_BOX_SIZE = 0.0001
local ZERO_VECTOR = { 0, 0 }
---@type data.WireConnectionPoint
local ZERO_CONNECTION_POINT = {
	wire = { green = ZERO_VECTOR, red = ZERO_VECTOR },
	shadow = { green = ZERO_VECTOR, red = ZERO_VECTOR },
}

-- Base for invisible combinators
---@type data.CombinatorPrototype
local invisible_combinator_prototype = {
	-- PrototypeBase
	name = "DO_NOT_USE",
	type = "combinator",
	hidden_in_factoriopedia = true,

	-- EntityPrototype
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-blueprintable",
		"not-deconstructable",
		"not-upgradable",
		"hide-alt-info",
	},
	collision_mask = { layers = {} },
	collision_box = {
		{ -TINY_BOX_SIZE, -TINY_BOX_SIZE },
		{ TINY_BOX_SIZE, TINY_BOX_SIZE },
	},
	selection_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
	minable = nil,
	selectable_in_game = false,
	allow_copy_paste = false,
	created_smoke = nil,

	-- CombinatorPrototype
	active_energy_usage = "1W",
	energy_source = { type = "void" },
	circuit_wire_max_distance = 64,
	draw_circuit_wires = false,
	draw_copper_wires = false,
	activity_led_light_offsets = {
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
	},
	screen_light_offsets = {
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
	},
	-- Constant comb
	circuit_wire_connection_points = {
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
	},
	input_connection_points = {
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
	},
	output_connection_points = {
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
	},
	input_connection_bounding_box = {
		{ -TINY_BOX_SIZE, -TINY_BOX_SIZE },
		{ TINY_BOX_SIZE, TINY_BOX_SIZE },
	},
	output_connection_bounding_box = {
		{ -TINY_BOX_SIZE, -TINY_BOX_SIZE },
		{ TINY_BOX_SIZE, TINY_BOX_SIZE },
	},
}

-- Base for invisible CCs.
---@type data.ConstantCombinatorPrototype
local invisible_constant_combinator_prototype = {
	-- PrototypeBase
	name = "DO_NOT_USE",
	type = "constant-combinator",
	hidden_in_factoriopedia = true,

	-- EntityPrototype
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-blueprintable",
		"not-deconstructable",
		"not-upgradable",
		"hide-alt-info",
	},
	collision_mask = { layers = {} },
	collision_box = {
		{ -TINY_BOX_SIZE, -TINY_BOX_SIZE },
		{ TINY_BOX_SIZE, TINY_BOX_SIZE },
	},
	selection_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
	minable = nil,
	selectable_in_game = false,
	allow_copy_paste = false,
	created_smoke = nil,

	circuit_wire_connection_points = {
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
		ZERO_CONNECTION_POINT,
	},
	draw_circuit_wires = false,
	draw_copper_wires = false,
	activity_led_light_offsets = {
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
		ZERO_VECTOR,
	},
	circuit_wire_max_distance = 64,
}

-- Base for invisible undetonating landmines.
---@type data.LandMinePrototype
local invisible_land_mine_prototype = {
	-- PrototypeBase
	name = "DO_NOT_USE",
	type = "land-mine",
	hidden = true,
	hidden_in_factoriopedia = true,

	-- EntityPrototype
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-blueprintable",
		"not-deconstructable",
		"not-upgradable",
		"hide-alt-info",
	},
	collision_mask = { layers = {} },
	collision_box = {
		{ -TINY_BOX_SIZE, -TINY_BOX_SIZE },
		{ TINY_BOX_SIZE, TINY_BOX_SIZE },
	},
	selection_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
	minable = nil,
	selectable_in_game = false,
	allow_copy_paste = false,
	created_smoke = nil,

	-- EntityWithOwnerPrototype
	is_military_target = false,

	-- LandMinePrototype
	trigger_radius = 0,
	force_die_on_attack = false,
	trigger_collision_mask = { layers = {} },
	draw_copper_wires = false,
	draw_circuit_wires = false,
}

---@class (exact) things.CombinatorInvisibleVariants
---@field public unpowered string Name of the invisible combinator variant that has zero energy usage.
---@field public powered? string Name of the invisible combinator variant that has non-zero energy usage. Will fall back onto unpowered if not given.

---@class (exact) things.CombinatorRegistration
---@field public name string Name of the combinator registration. This should be the replaceable entity name.
---@field public type string Type of the combinator registration. This should be the entity type of the combinator.
---@field public invisible_variants? things.CombinatorInvisibleVariants If given, specifies the invisible combinator variants associated with this combinator.
---@field public private? boolean If true, this indicates to other mods that this combinator is not intended for player use. This is merely a hint and it is up to mod implementations to honor it appropriately.

---Register a combinator type during the data phase.
---@param registration things.CombinatorRegistration
function lib.register(registration)
	if helpers.stage ~= "prototype" then
		error(
			"Things registration helpers may only be used in the prototype stage."
		)
	end

	if not registration.name then
		error("Combinator registration must have a name.")
	end

	data.raw["mod-data"]["things-combinators"].data[registration.name] =
		registration
end

---Get a generic `CombinatorPrototype` with fields filled in as appropriate for an invisible combinator.
function lib.get_invisible_combinator_prototype()
	return tlib.deep_copy(invisible_combinator_prototype, true)
end

--- Get a generic `ConstantCombinatorPrototype` with fields filled in as appropriate for an invisible constant combinator.
function lib.get_invisible_constant_combinator_prototype()
	return tlib.deep_copy(invisible_constant_combinator_prototype, true)
end

--- Get a generic `LandMinePrototype` with fields filled in as appropriate for an invisible circuit-triggered landmine.
function lib.get_invisible_land_mine_prototype()
	return tlib.deep_copy(invisible_land_mine_prototype, true)
end

---@type table<string, things.CombinatorRegistration>
local control_cc_registry

if helpers.stage == "runtime" then
	control_cc_registry = (prototypes.mod_data["things-combinators"].data or {}) --[[@as table<string, things.CombinatorRegistration>]]
end

---Create an invisible device from a registered prototype.
---@param surface LuaSurface The surface to create the invisible device on.
---@param base_name string The base name of the device to create an invisible replacement for. This should be the name of a registered device.
---@param is_powered boolean If true, a powered variant will be used when possible.
---@param create_args table Args to pass to `LuaSurface.create_entity` when creating the invisible combinator. Note that many fields will be overridden to ensure proper behavior.
---@return string? err If the device could not be created, this will be a string describing the error.
---@return LuaEntity? invisible_device The invisible device entity, or nil if it could not be created.
local function create_invisible(surface, base_name, is_powered, create_args)
	local reg = control_cc_registry[base_name]
	if not reg then return "Device not registered", nil end
	local variants = reg.invisible_variants
	if not variants then return "Device has no invisible variants", nil end
	local variant = variants.unpowered
	if is_powered and variants.powered then variant = variants.powered end

	create_args.name = variant
	create_args.snap_to_grid = false
	create_args.fast_replace = false
	create_args.raise_built = true
	create_args.create_build_effect_smoke = false
	create_args.move_stuck_players = true
	create_args.preserve_ghosts_and_corpses = true

	local e =
		surface.create_entity(create_args --[[@as LuaSurface.create_entity_param]])
	if not e then return "Failed to create invisible device", nil end
	return nil, e
end
lib.create_invisible = create_invisible

---@class things.CombinatorNetwork
---@field public combinators things.NetworkCombinator[] The combinators in the network.
---@field public networks ["red"|"green", any...] The wire networks.

---@class things.NetworkCombinator
---@field public name string Combinator entity name
---@field public type string Combinator entity type
---@field public control table Circuit network control behavior
---@field public in_red? uint Input red wire network
---@field public in_green? uint Input green wire network
---@field public out_red? uint Output red wire network
---@field public out_green? uint Output green wire network

---@class things.NetworkConstantCombinator : things.NetworkCombinator
---@field public type "constant-combinator"
---@field public control LogisticSections

---@class things.NetworkArithmeticCombinator : things.NetworkCombinator
---@field public type "arithmetic-combinator"
---@field public control ArithmeticCombinatorParameters

---@class things.NetworkDeciderCombinator : things.NetworkCombinator
---@field public type "decider-combinator"
---@field public control DeciderCombinatorParameters

---@class things.NetworkSelectorCombinator : things.NetworkCombinator
---@field public type "selector-combinator"
---@field public control SelectorCombinatorParameters

return lib
