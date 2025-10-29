--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

local strace = require("lib.core.strace")
strace.set_handler(strace.standard_log_handler)

require("control.settings")
require("control.storage")
require("control.registration")

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

require("remote-interface")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end
