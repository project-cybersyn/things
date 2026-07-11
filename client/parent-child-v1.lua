local rcall = remote and remote.call

---@class things.client.ParentChildV1Lib
local lib = {}

---Get all children of a Thing.
---@param thing things.Id Thing ID to query. This function will return `nil` if the Thing does not exist.
---@return table<string,things.ThingChildInfo>? children A table mapping each child index to their corresponding ThingChildInfo. Returns an empty table if the Thing has no children.
function lib.get_children(thing)
	local _, children = rcall("things", "get_children", thing)
	return children
end

return lib
