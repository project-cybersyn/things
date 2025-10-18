local thing_names = prototypes.mod_data["things-names"].data --[[@as {[string]: things.ThingRegistration}]]

local thing_graphs = prototypes.mod_data["things-graphs"].data --[[@as {[string]: things.GraphRegistration}]]

---Check if a name is registered as a Thing name, and return its Registration if so.
---@param name string? The entity prototype name to check.
---@return things.ThingRegistration|nil The Thing Registration if the name is registered, or nil.
function _G.get_thing_registration(name) return thing_names[name or ""] end

---Check if a name is registered as a Thing graph, and return its Registration if so.
---@param name string? The graph name to check.
---@return things.GraphRegistration|nil The graph Registration if the name is registered, or nil.
function _G.get_graph_registration(name) return thing_graphs[name or ""] end
