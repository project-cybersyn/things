--------------------------------------------------------------------------------
-- THINGS CONTROL PHASE
--------------------------------------------------------------------------------

local event = require("lib.core.event")
local scheduler = require("lib.core.scheduler")
local actual = require("lib.core.blueprint.actual")

require("lib.core.debug-log")
set_print_debug_log(true)

-- Early init
require("control.events")
require("control.mod-data")
require("control.storage")
require("control.settings")
-- Late init
require("control.thing")
require("control.graph")
require("control.prebuild")
require("control.virtual-undo")
require("control.extraction")
require("control.application")
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

event.bind("on_init", raise_init)
on_init(function() raise_startup({}) end, true)
event.bind("on_load", raise_load)
event.bind("on_configuration_changed", raise_configuration_changed)
event.bind(defines.events.on_runtime_mod_setting_changed, function(event)
	update_mod_settings()
	raise_mod_settings_changed()
end)

--------------------------------------------------------------------------------
-- BLUEPRINTING
--------------------------------------------------------------------------------

event.bind(defines.events.on_player_setup_blueprint, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end
	local bp = actual.get_actual_blueprint(player, ev.record, ev.stack)
	if not bp then return end
	raise_blueprint_extract(ev, player, bp)
end)

event.bind(defines.events.on_pre_build, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end
	-- Blueprint
	if player.is_cursor_blueprint() then
		local bp = actual.get_actual_blueprint(
			player,
			player.cursor_record,
			player.cursor_stack
		)
		if not bp then return end
		return raise_blueprint_apply(player, bp, player.surface, ev)
	end
	-- Item with entity place result
	local stack = player.cursor_stack
	if stack and stack.valid_for_read then
		local entity_placed = stack.prototype.place_result
		if entity_placed then
			return raise_pre_build_entity(
				ev,
				player,
				entity_placed,
				stack.quality,
				player.surface
			)
		end
	end
	-- Ghost cursor
	local cursor_ghost = player.cursor_ghost
	if cursor_ghost then
		local entity_placed = cursor_ghost.name.place_result
		if entity_placed then
			return raise_pre_build_entity(
				ev,
				player,
				entity_placed,
				cursor_ghost.quality --[[@as LuaQualityPrototype]],
				player.surface
			)
		end
	end
end)

--------------------------------------------------------------------------------
-- CONSTRUCTION
--------------------------------------------------------------------------------

---@param ev AnyFactorioBuildEventData
local function handle_generic_built(ev)
	local player = ev.player_index and game.get_player(ev.player_index) or nil
	local entity = ev.entity
	if entity.type == "entity-ghost" then
		raise_built_ghost(ev, entity, entity.tags, player)
	else
		raise_built_real(ev, entity, ev.tags, player)
	end
end

event.bind(defines.events.on_built_entity, handle_generic_built)
event.bind(defines.events.on_robot_built_entity, handle_generic_built)
event.bind(defines.events.on_space_platform_built_entity, handle_generic_built)
event.bind(defines.events.on_entity_cloned, raise_entity_cloned)
event.bind(defines.events.script_raised_built, handle_generic_built)
event.bind(defines.events.script_raised_revive, handle_generic_built)

--------------------------------------------------------------------------------
-- DECONSTRUCTION AND DEATH
--------------------------------------------------------------------------------

local function handle_pre_destroyed(event)
	raise_unified_pre_destroy(event, event.entity, nil)
end

event.bind(defines.events.on_pre_player_mined_item, function(ev)
	if ev.player_index then
		raise_unified_pre_destroy(ev, ev.entity, game.get_player(ev.player_index))
	else
		raise_unified_pre_destroy(ev, ev.entity, nil)
	end
end)
event.bind(defines.events.on_robot_pre_mined, handle_pre_destroyed)
event.bind(defines.events.on_space_platform_pre_mined, handle_pre_destroyed)
event.bind(defines.events.on_pre_ghost_deconstructed, function(ev)
	-- Ghost deconstruction is special as it doesn't fire a destroy event.
	-- We synthesize it here.
	if ev.player_index then
		local player = game.get_player(ev.player_index)
		raise_unified_pre_destroy(ev, ev.ghost, player)
		raise_unified_destroy(ev, ev.ghost, player, true)
	else
		raise_unified_destroy(ev, ev.ghost, nil, false)
	end
end)

local function handle_destroyed(event)
	raise_unified_destroy(event, event.entity, nil, false)
end

event.bind(defines.events.on_player_mined_entity, function(ev)
	if ev.player_index then
		raise_unified_destroy(ev, ev.entity, game.get_player(ev.player_index), true)
	else
		raise_unified_destroy(ev, ev.entity, nil, false)
	end
end)
event.bind(defines.events.on_robot_mined_entity, handle_destroyed)
event.bind(defines.events.on_space_platform_mined_entity, handle_destroyed)
event.bind(defines.events.script_raised_destroy, function(ev)
	-- Script destruction isn't undo-able
	raise_unified_destroy(ev, ev.entity, nil, false)
end)

event.bind(defines.events.on_post_entity_died, raise_entity_died)

-- Marking and unmarking
event.bind(defines.events.on_marked_for_deconstruction, function(ev)
	if ev.player_index then
		raise_entity_marked(ev, ev.entity, game.get_player(ev.player_index))
	end
end)
event.bind(defines.events.on_cancelled_deconstruction, function(ev)
	if ev.player_index then
		raise_entity_unmarked(ev, ev.entity, game.get_player(ev.player_index))
	end
end)

-- Undo/redo

event.bind(defines.events.on_undo_applied, raise_undo_applied)
event.bind(defines.events.on_redo_applied, raise_redo_applied)

-- Orientation

event.bind(
	defines.events.on_player_flipped_entity,
	function(ev) raise_player_flipped_entity(ev, ev.entity) end
)

event.bind(
	defines.events.on_player_rotated_entity,
	function(ev) raise_player_rotated_entity(ev, ev.entity) end
)

-- Settings

event.bind(
	defines.events.on_entity_settings_pasted,
	function(ev) raise_entity_settings_pasted(ev, ev.source, ev.destination) end
)

-- API

remote.add_interface("things", _G.remote_interface)

-- Commands

-- XXX: remove
commands.add_command(
	"things-debug-undo-stack",
	"Debug undo stack",
	function(cmd)
		local player = game.get_player(cmd.player_index)
		if not player then return end
		local vups = get_undo_player_state(player.index)
		if not vups then return end
		local urs = player.undo_redo_stack
		if urs.get_undo_item_count() > 0 then
			debug_log("Top undo item:", urs.get_undo_item(1))
		end
		debug_log("Top markers", vups.top_marker_set)
	end
)
