local lib = {}

if helpers.stage ~= "prototype" then
	error(
		"Things registration helpers should only be used in the prototype stage."
	)
end

---Data-phase helper to register a Thing.
---@param registration things.ThingRegistration
function lib.register(registration)
	if not registration.name then
		error("Thing registration must have a name.")
	end

	data.raw["mod-data"]["things-names"].data[registration.name] = registration
end

return lib
