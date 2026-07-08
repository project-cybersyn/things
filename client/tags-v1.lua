local rcall = remote and remote.call

---@class things.client.TagsV1Lib
local lib = {}

---@param thing things.ThingIdentification
---@param tag_name string
---@return AnyBasic? tag_value The value of the tag, or nil if the tag is not set.
function lib.get_tag(thing, tag_name)
	local _, tag_value = rcall("things-tags-v1", "get_tag", thing, tag_name)
	return tag_value
end

return lib
