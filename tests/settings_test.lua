-- Settings saved under the old name are carried over to the new one, once.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local config = require("puppet.config")

local function memory(values)
  return {
    get = function(key) return values[key] end,
    set = function(key, value) values[key] = value end,
    clear = function(key) values[key] = nil end,
  }
end

local values = { ["ClaudePuppet.choice"] = { x = 1 } }
config.carryOverSettings(memory(values))
check("an old choice moves to the new key", values["Deskmates.choice"] and values["Deskmates.choice"].x == 1)
check("the old key is cleared", values["ClaudePuppet.choice"] == nil)

values = { ["ClaudePuppet.hidden"] = true, ["Deskmates.hidden"] = false }
config.carryOverSettings(memory(values))
check("a new value is never overwritten", values["Deskmates.hidden"] == false)
check("the old key is cleared when the new one is set", values["ClaudePuppet.hidden"] == nil)

values = {}
config.carryOverSettings(memory(values))
check("nothing set, nothing carried", next(values) == nil)

values = { ["ClaudePuppet.hidden"] = false }
config.carryOverSettings(memory(values))
check("a false old value is carried", values["Deskmates.hidden"] == false)
check("and its old key is cleared", values["ClaudePuppet.hidden"] == nil)

check.done("settings")
