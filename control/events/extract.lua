-- Events for extraction of blueprints.

local events = require("lib.core.event")
local extraction_lib = require("control.blueprint-extraction")
local actual = require("lib.core.blueprint.actual")
local strace = require("lib.core.strace")

events.bind(
	"cooperative-blueprinting-v1-on_extract",
	---@param ev CooperativeBlueprinting.OnExtract
	function(ev)
		if mod_settings.always_splice then
			strace.warn(
				"Debug: always_splice is enabled, rewriting blueprint on extract"
			)
			remote.call(
				"cooperative-blueprinting-v1",
				"_force_splice",
				ev.blueprint_key
			)
		end
	end
)

events.bind(
	"cooperative-blueprinting-v1-on_post_extract",
	---@param ev CooperativeBlueprinting.OnPostExtract
	function(ev) extraction_lib.extract_blueprint(ev.blueprint, ev.mapping) end
)
