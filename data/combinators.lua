local comb_reg = require("client.combinators-v1")
local tlib = require("lib.core.table")

local arithmetic = comb_reg.get_invisible_combinator_prototype()
arithmetic.type = "arithmetic-combinator"
arithmetic.name = "things-arithmetic-combinator-invisible"

local powered_arithmetic = tlib.deep_copy(arithmetic, true)
powered_arithmetic.name = "things-arithmetic-combinator-invisible-powered"
powered_arithmetic.energy_source =
	{ type = "electric", usage_priority = "secondary-input" }
powered_arithmetic.active_energy_usage = "1KW"

local decider = comb_reg.get_invisible_combinator_prototype()
decider.type = "decider-combinator"
decider.name = "things-decider-combinator-invisible"

local powered_decider = tlib.deep_copy(decider, true)
powered_decider.name = "things-decider-combinator-invisible-powered"
powered_decider.energy_source =
	{ type = "electric", usage_priority = "secondary-input" }
powered_decider.active_energy_usage = "1KW"

local selector = comb_reg.get_invisible_combinator_prototype()
selector.type = "selector-combinator"
selector.name = "things-selector-combinator-invisible"

local powered_selector = tlib.deep_copy(selector, true)
powered_selector.name = "things-selector-combinator-invisible-powered"
powered_selector.energy_source =
	{ type = "electric", usage_priority = "secondary-input" }
powered_selector.active_energy_usage = "1KW"

local constant = comb_reg.get_invisible_constant_combinator_prototype()
constant.type = "constant-combinator"
constant.name = "things-constant-combinator-invisible"

data:extend({
	arithmetic,
	powered_arithmetic,
	decider,
	powered_decider,
	selector,
	powered_selector,
	constant,
})

comb_reg.register({
	name = "arithmetic-combinator",
	type = "arithmetic-combinator",
	invisible_variants = {
		unpowered = "things-arithmetic-combinator-invisible",
		powered = "things-arithmetic-combinator-invisible-powered",
	},
})

comb_reg.register({
	name = "decider-combinator",
	type = "decider-combinator",
	invisible_variants = {
		unpowered = "things-decider-combinator-invisible",
		powered = "things-decider-combinator-invisible-powered",
	},
})

comb_reg.register({
	name = "selector-combinator",
	type = "selector-combinator",
	invisible_variants = {
		unpowered = "things-selector-combinator-invisible",
		powered = "things-selector-combinator-invisible-powered",
	},
})

comb_reg.register({
	name = "constant-combinator",
	type = "constant-combinator",
	invisible_variants = {
		unpowered = "things-constant-combinator-invisible",
	},
})
