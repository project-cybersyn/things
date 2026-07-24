local ty = require("types")
local ClientThing = require("client-thing-v1")
local combinators_v1 = require("combinators-v1")
local tags_v1 = require("tags-v1")
local parent_child_v1 = require("parent-child-v1")
local triggers_v1 = require("triggers-v1")
local graph_v1 = require("graph-v1")

local rcall
if helpers.stage == "runtime" then
	rcall = remote.call
else
	rcall = function() return nil, nil end
end

---@class things.client
local lib = {}

lib.combinators_v1 = combinators_v1
lib.tags_v1 = tags_v1
lib.parent_child_v1 = parent_child_v1
lib.triggers_v1 = triggers_v1
lib.graph_v1 = graph_v1

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

---Create a client-side representation of a Thing without querying the service. Because no checks are done, the Thing may not exist or may be invalid.
---@param id things.Id The id of the Thing to represent.
---@return things.client.ThingV1 client_thing A client side object representing the Thing.
function lib.represent(id) return ClientThing:new(id) end

---@param thing_identification things.ThingIdentification Either the id of a Thing, or the LuaEntity currently representing it.
---@return things.client.ThingV1? client_thing A client side object representing the Thing, or nil if the Thing does not exist.
function lib.get(thing_identification)
	local _, short = rcall("things-metadata-v1", "get", thing_identification)
	---@cast short things.ThingShortSummary?
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

---Given the entity that currently represents a Thing, get its ID.
---@param thing_entity LuaEntity? The entity that represents the Thing.
---@return things.Id? id The ID of the Thing, or nil if the entity does not represent a Thing.
function lib.get_thing_id(thing_entity)
	if not thing_entity or not thing_entity.valid then return nil end
	local id = rcall("things-ca-v1", "get_thing_id", thing_entity)
	---@cast id things.Id?
	return id
end

return lib
