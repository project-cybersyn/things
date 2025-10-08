local lib = {}

---Set of tag keys used by Things in blueprints. These are reserved for Things
---and other mods attempting to use them will cause conflicts.
lib.BLUEPRINT_TAG_SET = {
	-- Local ID
	["@i"] = true,
	-- Thing tags
	["@t"] = true,
	-- Children by local ID
	["@c"] = true,
	-- Parent by local ID
	["@p"] = true,
	-- Graph edges
	["@e"] = true,
}

lib.LOCAL_ID_TAG = "@i"
lib.TAGS_TAG = "@t"
lib.CHILDREN_TAG = "@c"
lib.GRAPH_EDGES_TAG = "@e"
lib.PARENT_TAG = "@p"

return lib
