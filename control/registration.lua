local tlib = require("lib.core.table")

---@type {[string]: things.ThingRegistration}
local thing_names = {}
for name, reg in pairs(prototypes.mod_data["things-names"].data) do
	thing_names[name] = tlib.assign(
		{},
		reg --[[@as things.ThingRegistration]],
		{ name = name }
	)
end

---@type {[string]: things.GraphRegistration}
local thing_graphs = {}
for name, reg in pairs(prototypes.mod_data["things-graphs"].data) do
	thing_graphs[name] = tlib.assign(
		{},
		reg --[[@as things.GraphRegistration]],
		{ name = name }
	)
end

local lib = {}

---Check if a name is registered as a Thing name, and return its Registration if so.
---@param name string? The entity prototype name to check.
---@return things.ThingRegistration|nil #The Thing Registration if the name is registered, or nil.
function lib.get_thing_registration(name) return thing_names[name or ""] end

---Check if a name is registered as a Thing graph, and return its Registration if so.
---@param name string? The graph name to check.
---@return things.GraphRegistration|nil #The graph Registration if the name is registered, or nil.
function lib.get_graph_registration(name) return thing_graphs[name or ""] end

---Check if a given entity prototype name should be intercepted for Thing creation.
---@param name string The entity prototype name to check.
---@return things.ThingRegistration|nil #The Thing Registration that should be associated to the built thing, or nil.
function lib.should_intercept_build(name)
	local reg = lib.get_thing_registration(name)
	if reg and reg.intercept_construction then return reg end
end

return lib
