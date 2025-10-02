local event = require("lib.core.event")

---@class (exact) things.Storage
---@field public things {[uint]: things.Thing} Things by thing id.
---@field public things_by_unit_number {[uint]: things.Thing} Things by unit_number of reified entity, if it exists.
---@field public thing_ghosts {[Core.WorldKey]: int} Map from ghost entity world keys to corresponding Thing IDs.
---@field public player_undo {[uint]: things.VirtualUndoPlayerState} Player undo states by player index.
---@field public extractions {[uint]: things.Extraction} Data for blueprints being extracted, indexed by extraction id
---@field public applications {[uint]: things.Application} Data for blueprints being applied, indexed by application id
---@field public player_prebuild {[uint]: things.PrebuildPlayerState} Data for prebuild operations.
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
	init_storage_key("extractions")
	init_storage_key("applications")
	init_storage_key("player_undo")
	init_storage_key("player_prebuild")
	init_storage_key("graphs")
end

-- TODO: eliminate for release
commands.add_command(
	"things-debug-init-storage",
	"Re-initialize Things storage (may lose data!)",
	function(ev) init_storage() end
)

-- Initialize storage on startup
event.bind("on_startup", init_storage, true)
