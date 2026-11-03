-- A click on a puppet brings its terminal forward, and a drag moves the row, judged by where the mouse events
-- happened: Hammerspoon may handle them late, after the mouse has already gone elsewhere.

local root = arg[0]:match("^(.*)/tests/") or "."
local stub = dofile(root .. "/tests/support/hs_stub.lua")
stub.spoonPath = root .. "/Deskmates.spoon/"
local check = dofile(root .. "/tests/support/check.lua")

local eventsFile = os.tmpname()
local function write(fields)
  local file = io.open(eventsFile, "a")
  file:write(os.time() .. "|" .. fields .. "\n")
  file:close()
end

local P = dofile(stub.spoonPath .. "init.lua")
P.eventsFile = eventsFile
P:start()
stub.tabs = "/dev/ttys001=1/1;"
write("UserPromptSubmit|tab1||||/dev-skill|app|iTerm.app||/dev/ttys001|claude|")
stub.advance(0.2)

local canvas = P.stage.puppets.tab1.canvas
local f = canvas:frame()
local function anchor() return P.stage.anchor.x .. "," .. P.stage.anchor.y end
-- The press as the canvas reports it; its position is deliberately wrong, as nothing may depend on it.
local function press() canvas.onMouse(canvas, "mouseDown", nil, 9999, -9999) end
local before = anchor()

-- A click handled late: by then the mouse is on its way to the terminal. No drag events came: a click.
stub.selected = nil
press()
stub.mouse = { x = f.x + 300, y = f.y - 200 }
stub.fire("leftMouseUp", f.x + 300, f.y - 200)
stub.advance(0.2)
check("a click handled late still selects its tab", stub.selected == "/dev/ttys001")
check("a click handled late leaves the puppets where they were", anchor() == before)

-- A click with a small wobble of the hand selects, and leaves the row exactly where it was.
stub.selected = nil
press()
stub.fire("leftMouseDragged", f.x + 10, f.y + 10)
stub.fire("leftMouseDragged", f.x + 11, f.y + 8)
stub.fire("leftMouseUp", f.x + 11, f.y + 8)
stub.advance(0.2)
check("a click with a wobble selects its tab", stub.selected == "/dev/ttys001")
check("a click with a wobble does not creep the row", anchor() == before)

-- A drag moves the row by what the mouse moved while dragging, and selects nothing.
stub.selected = nil
local from = { x = P.stage.anchor.x, y = P.stage.anchor.y }
press()
stub.mouse = { x = f.x + 500, y = f.y + 500 }
stub.fire("leftMouseDragged", f.x + 10, f.y + 10)
stub.fire("leftMouseDragged", f.x + 60, f.y - 20)
stub.fire("leftMouseUp", f.x + 60, f.y - 20)
stub.advance(0.2)
check("a drag moves the row by what the mouse moved", anchor() == (from.x + 50) .. "," .. (from.y - 30))
check("a drag selects nothing", stub.selected == nil)

-- A press whose release never came (Hammerspoon missed it) does not leave a tap moving the row later.
local moved = anchor()
press()
press()
stub.selected = nil
stub.fire("leftMouseUp", f.x + 10, f.y + 10)
local running = 0
for _, tap in ipairs(stub.taps) do if tap.running then running = running + 1 end end
check("only the last press is followed: no tap left running", running == 0)
check("only the last press is followed: the row stays", anchor() == moved)

-- A rabbit from Cursor's own chat (app "Cursor", no terminal) waits at its desk like any other, and a click
-- brings Cursor forward.
write("UserPromptSubmit|chat1|||||my-app|Cursor|||cursor|")
stub.advance(0.2)
write("Stop|chat1||||Done.|my-app|Cursor|||cursor|")
stub.advance(60)
check("Cursor's chat rabbit stays at its desk after the turn", P.stage.puppets.chat1 ~= nil and P.stage.puppets.chat1.canvas:isShowing())
stub.focused = nil
P:focus("chat1")
check("a click on Cursor's chat rabbit brings Cursor forward", stub.focused == "com.todesktop.230313mzl4w4u92")

os.remove(eventsFile)
check.done("click")
