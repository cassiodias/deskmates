-- The stage's row: desks in the order their sessions joined, the newest on the right at the anchor, as a new tab
-- opens on the right (Cassio, 7 Nov); the row grows leftwards, so it never runs off the right of the screen.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local Stage = require("puppet.stage.stage")
local config = require("puppet.config")

local nothing = function() end
local stage = Stage.new({ pixel = 4, anchor = { x = 1000, y = 800 }, onMouseDown = nothing, onMouseUp = nothing,
  onBubbleClick = nothing, onHover = nothing })
local palette = function() return { "#336699", "#993366", "#669933" } end
local step = config.W * 4 + config.GAP
local function x(key) return stage.puppets[key].canvas:topLeft().x end

stage:sync({ "first" }, palette)
check("one desk: at the anchor", x("first") == 1000)
stage:sync({ "first", "second" }, palette)
check("a new desk: on the right, at the anchor", x("second") == 1000)
check("the older one: a place to its left", x("first") == 1000 - step)
stage:sync({ "first", "second", "third" }, palette)
check("three: oldest leftmost", x("first") == 1000 - 2 * step and x("second") == 1000 - step and x("third") == 1000)
stage:sync({ "second", "third" }, palette)
check("one leaves: the rest close up to the anchor", x("second") == 1000 - step and x("third") == 1000)

check.done("stage")
