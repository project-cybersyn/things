-- Narrow-phase blueprinting events

local bind = require("control.events.typed").bind
local raise = require("control.events.typed").raise
local Application =
	require("control.infrastructure.blueprint-application").Application
local Extraction =
	require("control.infrastructure.blueprint-extraction").Extraction

-- Narrow-phase blueprint extraction event. Generates an `Extraction` object
-- that serves as manager for the overall operation.
bind("blueprint_extract", function(ev, player, bp)
	debug_log("on_blueprint_extract", ev)
	local lazy_bp_to_world = ev.mapping
	if not lazy_bp_to_world or not lazy_bp_to_world.valid then
		debug_log("on_blueprint_extract: no mapping")
		return
	end
	local bp_to_world = lazy_bp_to_world.get() --[[@as { [integer]: LuaEntity }|nil ]]
	if not bp_to_world then
		debug_log("on_blueprint_extract: empty mapping")
		return
	end

	local extraction = Extraction:new(bp, bp_to_world)
	if not extraction then
		debug_log("on_blueprint_extract: no Things in blueprint")
		return
	end
	raise("blueprint_extraction_started", extraction)
	raise("blueprint_extraction_finished", extraction)
	extraction:finish()
end)

-- Narrow-phase blueprint application event. Creates an `Application` object that
-- serves as manager for the overall operation.
bind("blueprint_apply", function(player, bp, surface, event)
	debug_log("on_blueprint_apply", player, bp, surface, event)
	-- Create application record
	Application:new(player, bp, surface, event)
end)
