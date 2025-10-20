local events = require("lib.core.event")

---@class (exact) things.Storage
---@field public things {[uint64]: things.Thing} Things by thing id.
---@field public things_by_unit_number {[uint64]: things.Thing} Things by unit_number of reified entity, if it exists.
---@field public thing_ghosts {[Core.WorldKey]: int} Map from ghost entity world keys to corresponding Thing IDs.
---@field public frames {[uint64]: things.Frame} Frames by tick_played.
---@field public graphs {[string]: things.Graph} Graphs by graph name.
storage = {}

local function init_storage_key(key, value)
	if value == nil then value = {} end
	if storage[key] == nil then storage[key] = value end
end

function _G.init_storage()
	init_storage_key("things")
	init_storage_key("things_by_unit_number")
	init_storage_key("thing_ghosts")
	init_storage_key("frames")
	init_storage_key("graphs")
end

-- TODO: eliminate for release
commands.add_command(
	"things-debug-init-storage",
	"Re-initialize Things storage (may lose data!)",
	function(ev) init_storage() end
)

-- Initialize storage on startup
events.bind("on_startup", init_storage, true)
