-- Narrow-phase blueprinting events

local bind = require("control.events.typed").bind

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
	extraction:map_things()
	extraction:map_edges()
	-- TODO: thing-thing relationships
	extraction:map_entities()

	extraction:destroy()
end)

-- Narrow-phase blueprint application event. Creates an `Application` object that
-- serves as manager for the overall operation. Unlike extractions, applications
-- have to be memory managed and garbage collected, because the associated
-- construction events will fire after the application event with no bookend
-- for overall operation completion.
bind("blueprint_apply", function(player, bp, surface, event)
	debug_log("on_blueprint_apply", player, bp, surface, event)
	-- GC old blueprint application records
	garbage_collect_applications()
	-- Create application record
	local application = Application:new(player, bp, surface, event)
	application:apply_overlapping_tags()
	application:map_overlapping_local_ids()
end)
