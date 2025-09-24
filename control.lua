--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

local counters = require("lib.core.counters")
local scheduler = require("lib.core.scheduler")
local events = require("lib.core.events")
local actual = require("lib.core.blueprint.actual")

local function debug_log(...)
	local x = table.pack(...)
	x.n = nil
	if #x == 1 then x = x[1] end
	if game then
		game.print(serpent.line(x, { nocode = true }), {
			skip = defines.print_skip.never,
			sound = defines.print_sound.never,
			game_state = false,
		})
	else
		log(serpent.line(x, { nocode = true }))
	end
end
_G.debug_log = debug_log
events.set_strace_handler(debug_log)

-- Early init
require("control.events")
require("control.storage")
require("control.settings")
-- Late init
require("control.thing")
require("control.virtual-undo")
require("control.extraction")
require("control.construction")
require("control.debug-overlay")
require("control.remote")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- MOD LIFECYCLE
--------------------------------------------------------------------------------

on_startup(counters.init, true)
on_startup(scheduler.init, true)

script.on_init(raise_init)
on_init(function() raise_startup({}) end, true)
script.on_load(raise_load)

script.on_configuration_changed(raise_configuration_changed)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	update_mod_settings()
	raise_mod_settings_changed()
end)

script.on_nth_tick(1, function(data) scheduler.tick(data) end)

--------------------------------------------------------------------------------
-- BLUEPRINTING
--------------------------------------------------------------------------------

script.on_event(defines.events.on_player_setup_blueprint, function(event)
	local player = game.get_player(event.player_index)
	if not player then return end
	local bp = actual.get_actual_blueprint(player, event.record, event.stack)
	if not bp then return end
	raise_blueprint_extract(event, player, bp)
end)

script.on_event(defines.events.on_pre_build, function(event)
	local player = game.get_player(event.player_index)
	if not player then return end
	-- Blueprint
	if player.is_cursor_blueprint() then
		local bp = actual.get_actual_blueprint(
			player,
			player.cursor_record,
			player.cursor_stack
		)
		if not bp then return end
		return raise_blueprint_apply(player, bp, player.surface, event)
	end
	-- Other buildable item
	raise_pre_build_from_item(event, player)
end)

--------------------------------------------------------------------------------
-- CONSTRUCTION
--------------------------------------------------------------------------------

---@param event AnyFactorioBuildEventData
local function handle_built_with_tags(event)
	raise_unified_build(event, event.entity, event.tags, nil)
end

script.on_event(defines.events.on_built_entity, function(event)
	if event.player_index then
		raise_unified_build(
			event,
			event.entity,
			event.tags,
			game.get_player(event.player_index)
		)
	else
		raise_unified_build(event, event.entity, event.tags, nil)
	end
end)
script.on_event(defines.events.on_robot_built_entity, handle_built_with_tags)
script.on_event(
	defines.events.on_space_platform_built_entity,
	handle_built_with_tags
)
script.on_event(defines.events.on_entity_cloned, raise_entity_cloned)
script.on_event(defines.events.script_raised_built, function()
	-- TODO: tags not present here
end)
script.on_event(defines.events.script_raised_revive, handle_built_with_tags)

--------------------------------------------------------------------------------
-- DECONSTRUCTION AND DEATH
--------------------------------------------------------------------------------

local function handle_pre_destroyed(event)
	raise_unified_pre_destroy(event, event.entity, nil)
end

script.on_event(defines.events.on_pre_player_mined_item, function(event)
	if event.player_index then
		raise_unified_pre_destroy(
			event,
			event.entity,
			game.get_player(event.player_index)
		)
	else
		raise_unified_pre_destroy(event, event.entity, nil)
	end
end)
script.on_event(defines.events.on_robot_pre_mined, handle_pre_destroyed)
script.on_event(
	defines.events.on_space_platform_pre_mined,
	handle_pre_destroyed
)
script.on_event(defines.events.on_pre_ghost_deconstructed, function(event)
	-- Ghost deconstruction is special as it doesn't fire a destroy event.
	-- We synthesize it here.
	if event.player_index then
		local player = game.get_player(event.player_index)
		raise_unified_pre_destroy(event, event.ghost, player)
		raise_unified_destroy(event, event.ghost, player, true)
	else
		raise_unified_destroy(event, event.ghost, nil, false)
	end
end)

local function handle_destroyed(event)
	raise_unified_destroy(event, event.entity, nil, false)
end

script.on_event(defines.events.on_player_mined_entity, function(event)
	if event.player_index then
		raise_unified_destroy(
			event,
			event.entity,
			game.get_player(event.player_index),
			true
		)
	else
		raise_unified_destroy(event, event.entity, nil, false)
	end
end)
script.on_event(defines.events.on_robot_mined_entity, handle_destroyed)
script.on_event(defines.events.on_space_platform_mined_entity, handle_destroyed)
script.on_event(defines.events.script_raised_destroy, function(event)
	-- Script destruction isn't undo-able
	raise_unified_destroy(event, event.entity, nil, false)
end)

script.on_event(defines.events.on_post_entity_died, raise_entity_died)

-- Marking and unmarking
script.on_event(defines.events.on_marked_for_deconstruction, function(event)
	if event.player_index then
		raise_entity_marked(
			event,
			event.entity,
			game.get_player(event.player_index)
		)
	end
end)
script.on_event(defines.events.on_cancelled_deconstruction, function(event)
	if event.player_index then
		raise_entity_unmarked(
			event,
			event.entity,
			game.get_player(event.player_index)
		)
	end
end)

-- Undo/redo

script.on_event(defines.events.on_undo_applied, raise_undo_applied)
script.on_event(defines.events.on_redo_applied, raise_redo_applied)

-- Orientation

script.on_event(
	defines.events.on_player_flipped_entity,
	function(event) raise_player_flipped_entity(event, event.entity) end
)

script.on_event(
	defines.events.on_player_rotated_entity,
	function(event) raise_player_rotated_entity(event, event.entity) end
)

-- Settings

script.on_event(
	defines.events.on_entity_settings_pasted,
	function(event)
		raise_entity_settings_pasted(event, event.source, event.destination)
	end
)

-- API

remote.add_interface("things", _G.remote_interface)
