-- Things API.

---@class (exact) things.Error
---@field public code string Machine-readable error code.
---@field public message LocalisedString Human-readable error message.

---Either the id of a Thing, or the LuaEntity currently representing it.
---@alias things.ThingIdentification int|LuaEntity

local CANT_BE_A_THING = {
	code = "cant_be_a_thing",
	message = "You may not use an entity that is nil, invalid, or didn't have a `unit_number` as a Thing or Thing identifier.",
}

local NOT_A_THING = {
	code = "not_a_thing",
	message = "The specified Thing does not exist.",
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

---Gets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
---@return Tags? tags The tags of the Thing, or `nil` if the Thing doesn't exist.
function remote_interface.get_tags(thing_identification)
	local thing = nil
	if type(thing_identification) ~= "number" then
		if
			not thing_identification.valid or not thing_identification.unit_number
		then
			return CANT_BE_A_THING
		end
		thing = get_thing_by_unit_number(thing_identification.unit_number)
	else
		thing = get_thing(thing_identification --[[@as int]])
	end
	if not thing then return nil, nil end
	return nil, thing.tags
end

---Sets the tags of a Thing.
---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@param tags Tags The new tags to set on the Thing.
---@return things.Error? error If the operation failed, the reason why. `nil` on success.
function remote_interface.set_tags(thing_identification, tags)
	local thing = nil
	if type(thing_identification) ~= "number" then
		if
			not thing_identification.valid or not thing_identification.unit_number
		then
			return CANT_BE_A_THING
		end
		thing = get_thing_by_unit_number(thing_identification.unit_number)
	else
		thing = get_thing(thing_identification --[[@as int]])
	end
	if not thing then return NOT_A_THING end
	thing:set_tags(tags)
	return nil
end
