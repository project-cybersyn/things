local oclass_lib = require("lib.core.orientation.orientation-class")

---@class things.client.OrientationV1Lib
local lib = {}

---Virtual orientation class allowing 4-way rotation with flipping (8 possible orientations)
lib.VO_4WAY_FLIP = oclass_lib.OrientationClass.D8_0_RF

return lib
