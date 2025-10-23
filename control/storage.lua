local events = require("lib.core.event")

---@class (exact) things.Storage
---@field public things {[int64]: things.Thing} Things by thing id.
---@field public things_by_unit_number {[uint64]: things.Thing} Things by unit_number of reified entity, if it exists.
---@field public current_frame things.Frame? The current construction frame, if any.
---@field public graphs {[string]: things.Graph} Graphs by graph name.
---@field public debug_overlays {[int64]: things.DebugOverlay} Debug overlays by thing id.
---@field public stored_opsets {[int64]: things.OpSet} Stored operation sets on the undo stack.
storage = {}

local function init_storage_key(key, value)
	if value == nil then value = {} end
	if storage[key] == nil then storage[key] = value end
end

function _G.init_storage()
	init_storage_key("things")
	init_storage_key("things_by_unit_number")
	init_storage_key("graphs")
	init_storage_key("debug_overlays")
	init_storage_key("stored_opsets")
end

-- TODO: eliminate for release
commands.add_command(
	"things-debug-init-storage",
	"Re-initialize Things storage (may lose data!)",
	function(ev) init_storage() end
)

-- Initialize storage on startup
events.bind("on_startup", init_storage, true)
