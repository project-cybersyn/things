-- Events for extraction of blueprints.

local events = require("lib.core.event")
local extraction_lib = require("control.blueprint-extraction")
local actual = require("lib.core.blueprint.actual")
local strace = require("lib.core.strace")

events.bind(
	"cooperative-blueprinting-v1-on_post_extract",
	---@param ev CooperativeBlueprinting.OnPostExtract
	function(ev) extraction_lib.extract_blueprint(ev.blueprint, ev.mapping) end
)
