local class = require("lib.core.class").class

local rcall

if helpers.stage == "runtime" then
	rcall = remote.call
else
	rcall = function() return nil, nil end
end

---@class things.client.ThingV1 A client side object representing a Thing. Safe for use in storage, but not guaranteed to be valid after asynchronous use.
---@field public id things.Id The unique id of the Thing.
---@field public name? string The name of the Thing's registration. If present, this is always valid, as it is immutable.
---@field public last_status? things.Status The last known status of the Thing. NOTE: This is a cached value and may not be accurate!
---@field public last_entity? LuaEntity The last known entity representing the Thing. NOTE: This is a cached value and may be inaccurate or invalid!
local ClientThingV1 = class("things.ClientThingV1")

function ClientThingV1:new(id)
	local obj = { id = id }
	return setmetatable(obj, self)
end

function ClientThingV1:refresh()
	---@type nil, things.ThingShortSummary?
	local _, short = rcall("things-metadata-v1", "get", self.id)
	if short then
		self.name = short.name
		self.last_status = short.status
		self.last_entity = short.entity
	else
		self.name = nil
		self.last_status = nil
		self.last_entity = nil
	end
end

---Get the value of a tag on this Thing.
---@param tag_name string The name of the tag to get.
---@param skip_cache? boolean If `true`, this will skip the cache and get the tag value directly from the server. This is slower, but more accurate.
---@return AnyBasic? tag_value The value of the tag, or `nil` if the Thing or the tag does not exist.
function ClientThingV1:get_tag(tag_name, skip_cache)
	---@type nil, string?
	local _, tag_value = rcall("things-tags-v1", "get_tag", self.id, tag_name)
	return tag_value
end

---Set the value of a tag on this Thing. If the Thing does not exist, this will do nothing.
---@param tag_name string The name of the tag to set.
---@param tag_value AnyBasic? The value to set the tag to. If `nil`, the tag will be removed.
function ClientThingV1:set_tag(tag_name, tag_value)
	rcall("things-tags-v1", "set_tag", self.id, tag_name, tag_value)
end

return ClientThingV1
