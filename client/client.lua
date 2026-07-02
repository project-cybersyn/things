local ty = require("types")
local ClientThing = require("client.client-thing-v1")
local combinators_v1 = require("client.combinators-v1")

local rcall
if helpers.stage == "runtime" then
	rcall = remote.call
else
	rcall = function() return nil, nil end
end

---@class things.client
local lib = {}

lib.combinators_v1 = combinators_v1

---Register a Thing type during the data phase.
---@param registration things.ThingRegistration
function lib.register(registration)
	if helpers.stage ~= "prototype" then
		error(
			"Things registration helpers may only be used in the prototype stage."
		)
	end

	if not registration.name then
		error("Thing registration must have a name.")
	end

	data.raw["mod-data"]["things-names"].data[registration.name] = registration
end

---Create a client-side representation of a Thing without querying the server. Because no checks are done, the Thing may not exist or may be invalid.
---@param id things.Id The id of the Thing to represent.
---@return things.client.ThingV1 client_thing A client side object representing the Thing.
function lib.represent(id) return ClientThing:new(id) end

---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.client.ThingV1? client_thing A client side object representing the Thing, or nil if the Thing does not exist.
function lib.get(thing_identification)
	---@type nil, things.ThingShortSummary?
	local _, short = rcall("things-metadata-v1", "get", thing_identification)
	if short then
		local ct = ClientThing:new(short.id)
		ct.name = short.name
		ct.last_status = short.status
		ct.last_entity = short.entity
		return ct
	else
		return nil
	end
end

return lib
