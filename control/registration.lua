local tlib = require("lib.core.table")

---@type {[string]: things.ThingRegistration}
local thing_names = {}
for name, reg in pairs(prototypes.mod_data["things-names"].data) do
	thing_names[name] =
		tlib.deep_copy(reg --[[@as things.ThingRegistration]], true)
	thing_names[name].name = name
end

---@type {[string]: things.GraphRegistration}
local thing_graphs = {}
for name, reg in pairs(prototypes.mod_data["things-graphs"].data) do
	thing_graphs[name] =
		tlib.deep_copy(reg --[[@as things.GraphRegistration]], true)
	thing_graphs[name].name = name
end

-- Check integrity of definitions.
for thing_key, thing_reg in pairs(thing_names) do
	if thing_reg.children then
		for index, child_def in pairs(thing_reg.children) do
			if child_def.create then
				local name = child_def.create.name
				if not name then
					error(
						"Thing Registration for '"
							.. thing_reg.name
							.. "' has a child at index '"
							.. tostring(index)
							.. "' with create instructions missing 'name'"
					)
				end
				if not thing_names[name] then
					error(
						"Thing Registration for '"
							.. thing_reg.name
							.. "' has a child at index '"
							.. tostring(index)
							.. "' with create instructions referencing unregistered name '"
							.. tostring(name)
							.. "'"
					)
				end
			end
		end
	end
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
