local rcall = remote and remote.call

---@class things.client.ParentChildV1Lib
local lib = {}

---Get all children of a Thing.
---@param thing things.Id Thing ID to query. This function will return `nil` if the Thing does not exist.
---@return table<string,things.ThingChildInfo>? children A table mapping each child index to their corresponding ThingChildInfo. Returns an empty table if the Thing has no children.
function lib.get_children(thing)
	local _, children = rcall("things", "get_children", thing)
	return children --[[@as table<string,things.ThingChildInfo>? ]]
end

--- Get a specific child of a Thing.
---@param thing things.Id Thing ID to query. This function will return `nil` if the Thing does not exist.
---@param child_index string The index of the child to retrieve.
---@return things.ThingChildInfo? child_info The information of the specified child. Returns `nil` if the child does not exist.
function lib.get_child(thing, child_index)
	local _, child_info = rcall("things", "get_child", thing, child_index)
	return child_info --[[@as things.ThingChildInfo? ]]
end

return lib
