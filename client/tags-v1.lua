local rcall = remote and remote.call

---@class things.client.TagsV1Lib
local lib = {}

---Get a tag from a Thing.
---@param thing things.Id Thing ID to query. This function will return `nil` if the Thing does not exist.
---@param tag_name string
---@return AnyBasic? tag_value The value of the tag
function lib.get_tag(thing, tag_name)
	local _, tag_value = rcall("things-tags-v1", "get_tag", thing, tag_name)
	return tag_value
end

---Get all tags from a Thing.
---@param thing things.Id Target Thing ID. This function will return `nil` if the Thing does not exist.
---@return Tags? tags The tags of the Thing, or nil if there are no tags.
function lib.get_tags(thing)
	local _, tags = rcall("things-tags-v1", "get_tags", thing)
	return tags --[[@as Tags? ]]
end

---Set a tag on a Thing.
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tag_name string
---@param tag_value AnyBasic? The value of the tag, or nil to remove the tag.
function lib.set_tag(thing, tag_name, tag_value)
	rcall("things-tags-v1", "set_tag", thing, tag_name, tag_value)
end

---Set all tags on a Thing.
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tags Tags The new tags for the Thing. This will replace all existing tags on the Thing. An empty table will remove all tags.
function lib.set_tags(thing, tags)
	rcall("things-tags-v1", "set_tags", thing, tags)
end

---Shallow merge tags into the tags of a Thing. Existing tags with the same key will be overwritten, and new tags will be added. Tags not present in the `tags` parameter will remain unchanged.
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param tags Tags The tags to merge into the Thing's existing tags.
function lib.merge_tags(thing, tags) rcall("things", "merge_tags", thing, tags) end

---Attach transient data to a Thing.
---@param thing things.Id Target Thing ID. This function will do nothing if the Thing does not exist.
---@param key string The key of the transient data.
---@param value (AnyBasic|LuaObject)? The value of the transient data. If `nil`, the transient data will be removed.
function lib.set_transient_data(thing, key, value)
	rcall("things", "set_transient_data", thing, key, value)
end

---Get transient data from a Thing.
---@param thing things.Id Target Thing ID. This function will return `nil` if the Thing does not exist.
---@param key string The key of the transient data.
---@return (AnyBasic|LuaObject)? value The value of the transient data, or nil if it does not exist.
function lib.get_transient_data(thing, key)
	local _, value = rcall("things", "get_transient_data", thing, key)
	return value
end

return lib
