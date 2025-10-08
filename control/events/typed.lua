-- Type definitions for events.

local event = require("lib.core.event")

local lib = {}

---@alias AnyFactorioBuildEventData EventData.script_raised_built|EventData.script_raised_revive|EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_entity_cloned|EventData.on_space_platform_built_entity

---@alias AnyFactorioPreDestroyEventData EventData.on_pre_player_mined_item|EventData.on_robot_pre_mined|EventData.on_space_platform_pre_mined|EventData.on_pre_ghost_deconstructed

---@alias AnyFactorioDestroyEventData EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy

---@overload fun(name: "mod_settings_changed")
---@overload fun(name: "built_real", ev: AnyFactorioBuildEventData, entity: LuaEntity, tags: Tags, player: LuaPlayer|nil)
---@overload fun(name: "built_ghost", ev: AnyFactorioBuildEventData, ghost: LuaEntity, tags: Tags, player: LuaPlayer|nil)
---@overload fun(name: "blueprint_extract", ev: EventData.on_player_setup_blueprint, player: LuaPlayer, bp: Core.Blueprintish)
---@overload fun(name: "blueprint_apply", player: LuaPlayer, bp: Core.Blueprintish, surface: LuaSurface, event: EventData.on_pre_build)
---@overload fun(name: "pre_build_entity", event: EventData.on_pre_build, player: LuaPlayer, entity_prototype: LuaEntityPrototype, quality: LuaQualityPrototype, surface: LuaSurface)
---@overload fun(name: "unified_pre_destroy", ev: AnyFactorioPreDestroyEventData, entity: LuaEntity, player: LuaPlayer|nil)
---@overload fun(name: "unified_destroy", ev: AnyFactorioDestroyEventData, entity: LuaEntity, player: LuaPlayer|nil, leave_undo_marker: boolean)
---@overload fun(name: "entity_cloned", ev: EventData.on_entity_cloned)
---@overload fun(name: "entity_marked", ev: EventData.on_marked_for_deconstruction, entity: LuaEntity, player: LuaPlayer)
---@overload fun(name: "entity_unmarked", ev: EventData.on_cancelled_deconstruction, entity: LuaEntity, player: LuaPlayer)
---@overload fun(name: "entity_died", ev: EventData.on_post_entity_died)
---@overload fun(name: "undo_applied", ev: EventData.on_undo_applied)
---@overload fun(name: "redo_applied", ev: EventData.on_redo_applied)
---@overload fun(name: "thing_initialized", thing: things.Thing)
---@overload fun(name: "thing_status", thing: things.Thing, old_status: string)
---@overload fun(name: "thing_tags_changed", thing: things.Thing, old_tags: Tags)
---@overload fun(name: "thing_edges_changed", thing: things.Thing, graph_name: string, change: "created"|"deleted"|"data_changed"|"status_changed", nodes: {[int]: true}, edges: things.GraphEdge[])
---@overload fun(name: "thing_children_changed", thing: things.Thing, added: things.Thing|nil, removed: things.Thing[]|nil)
---@overload fun(name: "thing_parent_changed", thing: things.Thing, old_parent_id: int|nil)
---@overload fun(name: "thing_child_status", parent: things.Thing, child: things.Thing, old_status: string)
---@overload fun(name: "thing_parent_status", child: things.Thing, parent: things.Thing, old_status: string)
---@overload fun(name: "blueprint_extraction_started", extraction: things.Extraction)
---@overload fun(name: "blueprint_extraction_finished", extraction: things.Extraction)
lib.raise = event.raise

---@overload fun(name: "mod_settings_changed", handler: fun(), first?: boolean)
---@overload fun(name: "built_real", handler: fun(ev: AnyFactorioBuildEventData, entity: LuaEntity, tags: Tags, player: LuaPlayer|nil), first?: boolean)
---@overload fun(name: "built_ghost", handler: fun(ev: AnyFactorioBuildEventData, ghost: LuaEntity, tags: Tags, player: LuaPlayer|nil), first?: boolean)
---@overload fun(name: "blueprint_extract", handler: fun(ev: EventData.on_player_setup_blueprint, player: LuaPlayer, bp: Core.Blueprintish), first?: boolean)
---@overload fun(name: "blueprint_apply", handler: fun(player: LuaPlayer, bp: Core.Blueprintish, surface: LuaSurface, event: EventData.on_pre_build), first?: boolean)
---@overload fun(name: "pre_build_entity", handler: fun(event: EventData.on_pre_build, player: LuaPlayer, entity_prototype: LuaEntityPrototype, quality: LuaQualityPrototype, surface: LuaSurface), first?: boolean)
---@overload fun(name: "unified_pre_destroy", handler: fun(ev: AnyFactorioPreDestroyEventData, entity: LuaEntity, player: LuaPlayer|nil), first?: boolean)
---@overload fun(name: "unified_destroy", handler: fun(ev: AnyFactorioDestroyEventData, entity: LuaEntity, player: LuaPlayer|nil, leave_undo_marker: boolean), first?: boolean)
---@overload fun(name: "entity_cloned", handler: fun(ev: EventData.on_entity_cloned), first?: boolean)
---@overload fun(name: "entity_marked", handler: fun(ev: EventData.on_marked_for_deconstruction, entity: LuaEntity, player: LuaPlayer), first?: boolean)
---@overload fun(name: "entity_unmarked", handler: fun(ev: EventData.on_cancelled_deconstruction, entity: LuaEntity, player: LuaPlayer), first?: boolean)
---@overload fun(name: "entity_died", handler: fun(ev: EventData.on_post_entity_died), first?: boolean)
---@overload fun(name: "undo_applied", handler: fun(ev: EventData.on_undo_applied), first?: boolean)
---@overload fun(name: "redo_applied", handler: fun(ev: EventData.on_redo_applied), first?: boolean)
---@overload fun(name: "thing_initialized", handler: fun(thing: things.Thing), first?: boolean)
---@overload fun(name: "thing_status", handler: fun(thing: things.Thing, old_status: string), first?: boolean)
---@overload fun(name: "thing_tags_changed", handler: fun(thing: things.Thing, old_tags: Tags), first?: boolean)
---@overload fun(name: "thing_edges_changed", handler: fun(thing: things.Thing, graph_name: string, change: "created"|"deleted"|"data_changed"|"status_changed", nodes: {[int]: true}, edges: things.GraphEdge[]), first?: boolean)
---@overload fun(name: "thing_children_changed", handler: fun(thing: things.Thing, added: things.Thing|nil, removed: things.Thing[]|nil), first?: boolean)
---@overload fun(name: "thing_parent_changed", handler: fun(thing: things.Thing, old_parent_id: int|nil), first?: boolean)
---@overload fun(name: "thing_child_status", handler: fun(parent: things.Thing, child: things.Thing, old_status: string), first?: boolean)
---@overload fun(name: "thing_parent_status", handler: fun(child: things.Thing, parent: things.Thing, old_status: string), first?: boolean)
---@overload fun(name: "blueprint_extraction_started", handler: fun(extraction: things.Extraction), first?: boolean)
---@overload fun(name: "blueprint_extraction_finished", handler: fun(extraction: things.Extraction), first?: boolean)
lib.bind = event.bind

return lib
