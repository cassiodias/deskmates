-- A session's plan as the Spoon reads it: the neutral file a translator writes (hook/plan-lib.sh), its progress,
-- and the sweep that clears plans no session needs any more.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/Deskmates.spoon/lib/?.lua;" .. root .. "/Deskmates.spoon/lib/?/init.lua;" .. package.path
local check = dofile(root .. "/tests/support/check.lua")
local plans = require("puppet.model.plans")

local function write(path, text)
  local file = io.open(path, "w")
  file:write(text)
  file:close()
end
local function exists(path)
  local file = io.open(path, "r")
  if file then file:close() end
  return file ~= nil
end

-- decode: the JSON a translator writes, and nothing it does not.
local d = plans.decode('{"a": [1, -2.5e1, true, false, null], "s": "x\\"y\\\\z\\n\\u00e9\\ud83d\\ude00", "o": {}}')
check("decode: an object", type(d) == "table")
check("decode: numbers", d and d.a[1] == 1 and d.a[2] == -25)
check("decode: true and false", d and d.a[3] == true and d.a[4] == false)
check("decode: null leaves a hole", d and d.a[5] == nil)
check("decode: escapes, \\u and a surrogate pair", d and d.s == 'x"y\\z\né😀')
check("decode: an empty object", d and type(d.o) == "table")
check("decode: truncated is nil", plans.decode('{"steps": [') == nil)
check("decode: trailing text is nil", plans.decode('{} x') == nil)
check("decode: not JSON is nil", plans.decode("steps") == nil)
check("decode: empty is nil", plans.decode("") == nil)

-- load: the fixtures the translator tests leave, read back.
local fixtures = root .. "/harnesses/claude/fixtures/"
local todo = plans.load(fixtures .. "plan-todowrite.plan")
check("load: a fixture plan", todo ~= nil and #todo.steps == 3)
check("load: a step's fields", todo and todo.steps[2].id == "2" and todo.steps[2].title == "Fixed the typo."
  and todo.steps[2].status == "active")
local doc = plans.load(fixtures .. "plan-exit-file.plan")
check("load: the plan's markdown", doc and doc.markdown == "# Add a flag\n\nFixed the typo.\n")
check("load: no markdown when there is none", todo and todo.markdown == nil)
check("load: a missing file is nil", plans.load(fixtures .. "no-such.plan") == nil)

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")
write(dir .. "/odd.json", '{"steps": [{"id": "1", "title": "Fixed the typo.", "status": "lost"},'
  .. '{"id": 2, "title": "x", "status": "done"}, {"id": "3", "title": "Run the tests", "status": "done"}],'
  .. '"plan": {"markdown": 5}}')
local odd = plans.load(dir .. "/odd.json")
check("load: only steps of the neutral shape are kept", odd and #odd.steps == 1 and odd.steps[1].id == "3")
check("load: markdown that is not text is dropped", odd and odd.markdown == nil)
write(dir .. "/list.json", "[1, 2]")
check("load: a file that is not a plan is nil", plans.load(dir .. "/list.json") == nil)
write(dir .. "/half.json", '{"steps": [{"id": "1"')
check("load: a half-written file is nil", plans.load(dir .. "/half.json") == nil)

-- progress and hasContent.
local p = plans.progress(todo)
check("progress: done and total", p.done == 1 and p.total == 3)
check("progress: the active step", p.active == "Fixed the typo.")
local none = plans.progress(nil)
check("progress: no plan", none.done == 0 and none.total == 0 and none.active == nil)
check("hasContent: steps", plans.hasContent(todo))
check("hasContent: markdown only", plans.hasContent({ steps = {}, markdown = "# Plan" }))
check("hasContent: an empty plan has none", not plans.hasContent({ steps = {}, markdown = "" }))
check("hasContent: no plan", not plans.hasContent(nil))

-- path: the same rule as plan_file in hook/plan-lib.sh.
check("path: a session's file", plans.path("/p", "s1") == "/p/s1.json")
check("path: dots and dashes", plans.path("/p", "a.b-c_1") == "/p/a.b-c_1.json")
check("path: a slash is refused", plans.path("/p", "../evil") == nil)
check("path: two dots are refused", plans.path("/p", "..") == nil)
check("path: empty is refused", plans.path("/p", "") == nil)

-- sweep: keeps the plans of sessions on the desk and young ones, deletes old and broken ones.
os.execute("rm -f '" .. dir .. "'/*")
write(dir .. "/live.json", '{"steps": [], "updatedAt": 0}')
write(dir .. "/young.json", '{"steps": [], "updatedAt": 9000}')
write(dir .. "/old.json", '{"steps": [], "updatedAt": 100}')
write(dir .. "/broken.json", '{"steps": [')
write(dir .. "/notes.txt", "kept")
plans.sweep(dir, { live = true }, 10000, 7200)
check("sweep: a live session's plan stays", exists(dir .. "/live.json"))
check("sweep: a young plan stays", exists(dir .. "/young.json"))
check("sweep: an old plan goes", not exists(dir .. "/old.json"))
check("sweep: a broken plan goes", not exists(dir .. "/broken.json"))
check("sweep: other files stay", exists(dir .. "/notes.txt"))
plans.sweep(dir .. "/missing", {}, 10000, 7200)
check("sweep: a missing folder is fine", true)
os.execute("rm -rf '" .. dir .. "'")

check.done("plans")
