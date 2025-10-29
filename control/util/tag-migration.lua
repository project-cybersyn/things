local tlib = require("lib.core.table")
local constants = require("control.constants")
local strace = require("lib.core.strace")

local pairs = pairs
local TAGS_TAG = constants.TAGS_TAG
local BLUEPRINT_TAG_SET = constants.BLUEPRINT_TAG_SET

local lib = {}

---@param tags Tags
---@param registration things.ThingRegistration
---@return Tags?
function lib.get_migrated_tags(tags, registration)
	local real_tags = tags[TAGS_TAG] --[[@as Tags?]]
	local migrate_callback = registration.migrate_tags_callback
	if migrate_callback then
		local unauthorized_tags = nil
		for k, _ in pairs(tags) do
			if not BLUEPRINT_TAG_SET[k] then
				unauthorized_tags = unauthorized_tags or {}
				unauthorized_tags[k] = tags[k]
			end
		end
		if unauthorized_tags then
			strace.debug(
				"Invoking tag migration callback for Thing",
				registration.name,
				"with unauthorized tags:",
				unauthorized_tags
			)
			local migrated_tags =
				remote.call(migrate_callback[1], migrate_callback[2], unauthorized_tags) --[[@as Tags?]]
			if migrated_tags then
				if real_tags then
					tlib.assign(real_tags, migrated_tags)
				else
					real_tags = migrated_tags
				end
			end
			strace.debug(
				"Tag migration callback for Thing",
				registration.name,
				"returned migrated tags:",
				migrated_tags
			)
		end
	end
	return real_tags
end

return lib
