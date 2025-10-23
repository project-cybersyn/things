local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local urs_lib = require("lib.core.undo-redo-stack")
local tr_lib = require("lib.core.relm.table-renderer")

local Pr = relm.Primitive
local VF = ultros.VFlow
local HF = ultros.HFlow

--------------------------------------------------------------------------------
-- Control
--------------------------------------------------------------------------------

---@return Relm.Handle?
---@return int?
local function get_debugger(player_index)
	local result_handle, result_id = nil, nil
	relm.root_foreach(function(handle, id, _, pi)
		if pi == player_index then
			result_handle = handle
			result_id = id
		end
	end)
	return result_handle, result_id
end

local function close_debugger(player_index)
	local _, id = get_debugger(player_index)
	relm.root_destroy(id)
end

local function open_debugger(player_index)
	local _, opened_id = get_debugger(player_index)
	if opened_id then return false end
	local player = game.get_player(player_index)
	if not player then return false end
	local screen = player.gui.screen
	local id, elt = relm.root_create(
		screen,
		"UndoStackDebuggerWindow",
		"things.UndoStackDebuggerWindow",
		{
			player_index = player_index,
		}
	)
	if not id then return false end
	return true
end

commands.add_command(
	"things-undo-stack-debugger",
	"Toggle the undo stack debugger window",
	function(cmd)
		local index = cmd.player_index
		if not index then return end
		open_debugger(index)
	end
)

--------------------------------------------------------------------------------
-- UI elements
--------------------------------------------------------------------------------

local Vups = relm.define_element({
	name = "things.Vups",
	render = function(props)
		return tr_lib.render_table(2, props.vups, nil, tr_lib.default_renderer)
	end,
})

local Stack = relm.define_element({
	name = "things.Stack",
	render = function(props)
		local view = props.view --[[@as Core.UndoRedoStackView]]
		local rows = {}
		for i = 1, view.get_item_count() do
			local item = view.get_item(i)
			rows[props.name .. i] = item
		end
		return tr_lib.render_table(2, rows, nil, tr_lib.default_renderer)
	end,
	message = function(me, payload, props, state) return false end,
})

local UndoStackEntries = relm.define_element({
	name = "things.UndoStackEntries",
	render = function(props)
		local player = props.player --[[@as LuaPlayer]]
		local urs = player.undo_redo_stack
		local undo_view = urs_lib.make_undo_stack_view(urs)
		local redo_view = urs_lib.make_redo_stack_view(urs)
		relm_util.use_event("things.frame_ended")

		return VF({ horizontally_stretchable = true }, {
			HF({ horizontally_stretchable = true }, {
				Stack({ name = "undo", view = undo_view }),
				Stack({ name = "redo", view = redo_view }),
			}),
		})
	end,
	message = function(me, payload, props, state)
		if payload.key == "things.frame_ended" then
			relm.paint(me)
			return true
		end
		return false
	end,
})

relm.define_element({
	name = "things.UndoStackDebuggerWindow",
	render = function(props)
		local player = game.get_player(props.player_index)
		local child = nil
		if not player then
			child = ultros.Label("Invalid state")
		else
			child = UndoStackEntries({
				player_index = player.index,
				player = player,
			})
		end

		return ultros.WindowFrame({
			caption = "Undo Stack Debugger",
		}, {
			Pr({
				type = "scroll-pane",
				direction = "vertical",
				width = 400,
				height = 400,
			}, { child }),
		})
	end,
	message = function(me, payload, props, state)
		if payload.key == "close" then
			close_debugger(props.player_index)
			return true
		end
		return false
	end,
})
