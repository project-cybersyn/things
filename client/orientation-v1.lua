local oclass_lib = require("lib.core.orientation.orientation-class")
local dihedral = require("lib.core.math.dihedral")

local dih_encode = dihedral.encode

---@class things.client.OrientationV1Lib
local lib = {}

---Virtual orientation class allowing 4-way rotation with flipping (8 possible orientations)
lib.VO_4WAY_FLIP = oclass_lib.OrientationClass.D8_0_RF

lib.RO_IDENTITY = dih_encode(4, 0, 0)
lib.RO_R1 = dih_encode(4, 1, 0)
lib.RO_R2 = dih_encode(4, 2, 0)
lib.RO_R3 = dih_encode(4, 3, 0)

return lib
