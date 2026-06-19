local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local urs_lib = require("lib.core.undo-redo-stack")
local tr_lib = require("lib.core.relm.table-renderer")
local constants = require("control.constants")

local UNDO_TAG = constants.UNDO_TAG

local Pr = relm.Primitive
local VF = ultros.VFlow
local HF = ultros.HFlow

--------------------------------------------------------------------------------
-- Control
--------------------------------------------------------------------------------

local function open_debugger(player_index)
	local player = game.get_player(player_index)
	if not player then return false end
	local screen = player.gui.screen
	local id, elt = relm.root_create(
		screen,
		"UndoStackDebuggerWindow",
		"things.UndoStackDebuggerWindow",
		{
			player = player,
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

local Stack = relm.define_element({
	name = "things.Stack",
	render = function(props)
		local view = props.view --[[@as Core.UndoRedoStackView]]
		local set_opset = props.set_opset or function() end
		local entries = {
			ultros.BoldLabel("I"),
			ultros.BoldLabel("A"),
			ultros.BoldLabel("Opset"),
			ultros.BoldLabel("Info"),
		}
		for i = 1, view.get_item_count() do
			local actions = view.get_item(i)
			local counter = table_size(actions)
			local j = 1
			if counter == 0 then
				entries[#entries + 1] = ultros.Label(tostring(i))
				entries[#entries + 1] = ultros.Label("nil")
				entries[#entries + 1] = ultros.Label("nil")
				entries[#entries + 1] = ultros.Label("EMPTY ACTION")
			end
			while counter > 0 do
				entries[#entries + 1] = ultros.Label(tostring(i))
				entries[#entries + 1] = ultros.Label(tostring(j))
				local action = actions[j]
				if action then
					local tags = action.tags
					local opset_id = (tags and tags[UNDO_TAG] and tags[UNDO_TAG][1])
					if opset_id then
						entries[#entries + 1] = ultros.Button({
							caption = tostring(opset_id),
							width = 30,
							height = 20,
							on_click = function() set_opset(opset_id) end,
						})
					else
						entries[#entries + 1] = ultros.Label("nil")
					end
					entries[#entries + 1] = ultros.Label(
						serpent.line(action.type, { comment = false, nocode = true })
					)
					counter = counter - 1
				else
					entries[#entries + 1] = ultros.Label("nil")
					entries[#entries + 1] = ultros.Label("NIL")
				end
				j = j + 1
			end
		end
		return Pr({
			type = "frame",
			style = "inside_shallow_frame",
			direction = "vertical",
			vertically_stretchable = true,
			width = 400,
			minimal_height = 600,
		}, {
			ultros.WellHeader({ caption = props.name }),
			Pr({
				type = "scroll-pane",
				direction = "vertical",
				vertically_stretchable = true,
				vertical_scroll_policy = "always",
				horizontal_scroll_policy = "never",
				extra_top_padding_when_activated = 0,
				extra_left_padding_when_activated = 0,
				extra_right_padding_when_activated = 0,
				extra_bottom_padding_when_activated = 0,
			}, {
				Pr({
					type = "table",
					column_count = 4,
					draw_horizontal_lines = true,
					draw_vertical_lines = true,
				}, entries),
			}),
		})
	end,
	message = function(me, payload, props, state) return false end,
})

local SingleOpset = relm.define("things.SingleOpset", function(props)
	local opset_id = props.opset
	local opset = storage.stored_opsets[opset_id or ""]
	if not opset then return ultros.Label("No opset selected") end
	local ops = opset.by_index or {}
	return ultros.RtMultilineLabel(
		serpent.line(ops, { comment = false, nocode = true })
	)
end)

local AllOpsets = relm.define("things.AllOpsets", function(props)
	local opsets = storage.stored_opsets
	local entries = { ultros.BoldLabel("Opset ID"), ultros.BoldLabel("Opset") }
	for id, opset in pairs(opsets) do
		entries[#entries + 1] = ultros.Label(tostring(id))
		entries[#entries + 1] =
			ultros.Label(serpent.line(opset, { comment = false, nocode = true }))
	end
	return Pr({
		type = "frame",
		style = "inside_shallow_frame",
		direction = "vertical",
		vertically_stretchable = true,
		width = 400,
		minimal_height = 600,
	}, {
		ultros.WellHeader({ caption = "All Opsets" }),
		Pr({
			type = "scroll-pane",
			direction = "vertical",
			vertically_stretchable = true,
			vertical_scroll_policy = "always",
			horizontal_scroll_policy = "never",
			extra_top_padding_when_activated = 0,
			extra_left_padding_when_activated = 0,
			extra_right_padding_when_activated = 0,
			extra_bottom_padding_when_activated = 0,
		}, {
			Pr({
				type = "table",
				column_count = 2,
				draw_horizontal_lines = true,
				draw_vertical_lines = true,
			}, entries),
		}),
	})
end)

local Opset = relm.define("things.Opset", function(props)
	local opset = props.opset
	if not opset then return AllOpsets({}) end
	return SingleOpset({ opset = opset })
end)

local Stacks = relm.define("things.Stacks", function(props)
	local player = props.player --[[@as LuaPlayer]]
	local urs = player.undo_redo_stack
	local undo_view = urs_lib.make_undo_stack_view(urs)
	local redo_view = urs_lib.make_redo_stack_view(urs)
	local opset, set_opset = relm.use_state(nil)

	return HF({
		Stack({ name = "redo", view = redo_view, set_opset = set_opset }),
		Stack({ name = "undo", view = undo_view, set_opset = set_opset }),
		Opset({ opset = opset }),
	})
end)

relm.define_element({
	name = "things.UndoStackDebuggerWindow",
	render = function(props)
		local player = props.player
		local child = nil
		if not player or not player.valid then
			child = ultros.Label("Invalid state")
		else
			child = Stacks({
				player_index = player.index,
				player = player,
			})
		end

		return ultros.WindowFrame({
			caption = "Things Undo Debugger",
		}, {
			child,
		})
	end,
	message = function(me, payload, props, state)
		if payload.key == "close" then
			relm.root_destroy(props.root_id)
			return true
		end
		return false
	end,
})
