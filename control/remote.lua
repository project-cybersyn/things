-- Things API.

---@class (exact) things.Error
---@field public code string Machine-readable error code.
---@field public message LocalisedString Human-readable error message.

local CANT_BE_A_THING = {
	code = "cant_be_a_thing",
	message = "Attempted to thingify an entity that was nil, invalid, or didn't have a `unit_number`.",
}

local UNKNOWN = {
	code = "unknown",
	message = "An unknown error occurred.",
}

local remote_interface = {}
_G.remote_interface = remote_interface

---Makes `entity` a Thing.
---@param entity LuaEntity
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return boolean? created True if a new Thing was created, false if the entity was already a Thing.
---@return int? thing_id The thing_id of the existing or newly created Thing.
function remote_interface.thingify(entity)
	if (not entity) or not entity.valid or not entity.unit_number then
		return CANT_BE_A_THING
	end
	local created, thing = thingify_entity(entity)
	if thing then
		return nil, created, thing.id
	else
		-- This should never happen
		return UNKNOWN
	end
end
