--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

local strace = require("lib.core.strace")
local relm = require("lib.core.relm.relm")
local event = require("lib.core.event")
local cbp =
	require("lib.cooperative-blueprinting.cooperative-blueprinting-control")
require("lib.core.debug-log") -- for debug_crash

relm.bootstrap_with_core_events(event)

strace.set_handler(strace.standard_log_handler)

require("client.types")

require("control.settings")
require("control.storage")
require("control.registration")

-- Bind Cooperative Blueprinting events first.
local binds = cbp.cooperative_blueprinting_control_phase()
if binds then
	for name, binding in ipairs(binds) do
		event.bind(name, binding)
	end
end

require("control.events.prebuild")
require("control.events.build")
require("control.events.orientation")
require("control.events.destroy")
require("control.events.undo")
require("control.events.extract")
require("control.events.cursor")
require("control.events.paste-settings")
require("control.events.downstream")

-- must be after `events.downstream`
require("control.automatic-children")

require("control.debug-overlay")
require("control.util.undo-stack-debugger")

require("control.doctor")

require("remote-interface")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
---@diagnostic disable-next-line: unresolved-require
if script.active_mods["gvv"] then require("__gvv__.gvv")() end
