-- The status texts: the line under the name tag and the card shown when the mouse rests on a puppet.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local status = require("puppet.model.status")

local function session(fields)
  local s = { agents = {}, order = {}, tools = 0, isWorking = false, summary = "", folder = "repo", tag = "repo",
    turnAt = 1000, seenAt = 1000 }
  for k, v in pairs(fields or {}) do s[k] = v end
  return s
end

local working = session({ isWorking = true, command = "review", tag = "review" })
check("a working command shows its folder and time", status.line(working, 1000 + 32 * 60) == "repo · 32m")
check("under a minute", status.line(working, 1030) == "repo · <1m")
check("over an hour", status.line(working, 1000 + 65 * 60) == "repo · 1h 5m")

local idle = session({ seenAt = 2000 })
check("the main conversation shows only the time, its tag is the folder", status.line(idle, 2000 + 12 * 60) == "idle 12m")
check("no folder, no folder", status.line(session({ folder = "", tag = "x", isWorking = true }), 1060) == "1m")

local waiting = session({ isWorking = true, mood = "permission", moodText = "Bash", seenAt = 1600, tag = "review" })
check("waiting counts from when it started to wait", status.line(waiting, 1600 + 3 * 60) == "repo · waiting 3m")

local busy = session({
  isWorking = true, command = "review", tag = "review", tools = 148, lastTool = "Bash",
  agents = { a = { done = false }, b = { done = false }, c = { done = true } }, order = { "a", "b", "c" },
})
local card = status.card(busy, 1000 + 32 * 60, "tab 2")
check("card: where", card[1] == "repo · tab 2")
check("card: what and how long", card[2] == "/review · working 32m")
check("card: subagents", card[3] == "subagents: 2 working, 1 done")
check("card: tools", card[4] == "148 tool calls · last: Bash")
check("card: nothing more while working", #card == 4)

local subagentsOnly = session({ agents = { a = { done = false } }, order = { "a" }, command = "review" })
check("background subagents still count as working", status.card(subagentsOnly, 1060)[2] == "/review · working 1m")

card = status.card(waiting, 1600 + 60)
check("card without a tab", card[1] == "repo")
check("card: waiting for permission", card[2] == "waiting for permission: Bash · 1m")
check("card: no subagents, no tools, no lines", #card == 2)

card = status.card(session({ mood = "asking", isWorking = true }), 1000)
check("card: waiting for an answer", card[2] == "waiting for your answer · <1m")

local done = session({ seenAt = 3000, tools = 1, lastTool = "Edit", summary = string.rep("word ", 20) })
card = status.card(done, 3000 + 5 * 60, "tab 1")
check("card: idle", card[2] == "idle 5m")
check("card: one tool call", card[3] == "1 tool call · last: Edit")
check("card: the last reply, shortened", card[4] and #card[4] <= 60 and card[4]:match("^last reply: word") and card[4]:match("…$"))

local titled = session({ isWorking = true, command = "review", title = "Shop-api PR 12 review, round two of the fixes",
  agents = { a = { done = false, label = "QA lens contract T-42" },
             b = { done = false, label = "QA lens break T-42" }, c = { done = true } },
  order = { "a", "b", "c" } })
card = status.card(titled, 1060, "tab 2")
check("card: the title first, shortened", card[1] == "Shop-api PR 12 review, round two of the…")
check("card: then where", card[2] == "repo · tab 2")
check("card: the working subagents by name", card[4] == "subagents: QA lens contract T-42, QA lens break T-42 working, 1 done")
local many = session({ agents = { a = { done = false, label = "x" }, b = { done = false, label = "y" },
  c = { done = false, label = "z" } }, order = { "a", "b", "c" } })
check("card: three or more working are counted", status.card(many, 1000)[3] == "subagents: 3 working")

check("card: a session with no folder still says something", status.card(session({ folder = "" }), 1000)[1] == "unknown folder")

check.done("status")
