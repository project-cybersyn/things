local lib = {}

---Set of tag keys used by Things in blueprints. These are reserved for Things
---and other mods attempting to use them will cause conflicts.
lib.BLUEPRINT_TAG_SET = {
	-- Local ID
	["@i"] = true,
	-- Thing name
	["@n"] = true,
	-- Thing tags
	["@t"] = true,
	-- Parent by local ID
	["@p"] = true,
	-- Graph edges
	["@e"] = true,
	-- Virtual orientation
	["@o"] = true,
	-- Undo/redo metadata
	["@u"] = true,
	-- Ghost revival tag
	["@g"] = true,
}

lib.LOCAL_ID_TAG = "@i"
lib.NAME_TAG = "@n"
lib.TAGS_TAG = "@t"
lib.GRAPH_EDGES_TAG = "@e"
lib.PARENT_TAG = "@p"
lib.ORIENTATION_TAG = "@o"
lib.UNDO_TAG = "@u"
lib.GHOST_REVIVAL_TAG = "@g"

---If an undo item has more actions than this, Things considers it degenerate.
lib.DEGENERATE_UNDO_ACTION_COUNT = 20000

return lib
