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
stub.tabs = "/dev/ttys009=1/1;/dev/ttys001=2/1;"
write("UserPromptSubmit|tab1||||/dev-skill|app|iTerm.app||/dev/ttys001|claude|")
stub.advance(0.2)

local canvas = P.stage.puppets.tab1.canvas
local f = canvas:frame()
local function anchor() return P.stage.anchor.x .. "," .. P.stage.anchor.y end
-- The press and release as the canvas reports them (the press's position deliberately wrong: nothing may
-- depend on it). The mouse tap the press starts may come too late to see the release of a quick click.
local function press() canvas.onMouse(canvas, "mouseDown", nil, 9999, -9999) end
local function release() canvas.onMouse(canvas, "mouseUp", nil, 9999, -9999) end
local function running()
  local n = 0
  for _, tap in ipairs(stub.taps) do if tap.running then n = n + 1 end end
  return n
end
local before = anchor()

-- A quick click: the release came before the tap started, so only the canvas saw it.
stub.selected, stub.raised = nil, nil
press()
stub.mouse = { x = f.x + 300, y = f.y - 200 }
release()
stub.advance(0.2)
check("a quick click selects its tab", stub.selected == "/dev/ttys001")
check("one click raises the tab's own window, in a second iTerm window too", stub.raised == 102)
check("a quick click leaves the puppets where they were", anchor() == before)
check("a quick click leaves no tap running", running() == 0)

-- A click the tap saw too, with a small wobble of the hand: selects once, and the row stays exactly put.
stub.selected = nil
press()
stub.fire("leftMouseDragged", f.x + 10, f.y + 10)
stub.fire("leftMouseDragged", f.x + 11, f.y + 8)
stub.fire("leftMouseUp", f.x + 11, f.y + 8)
release()
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
release()
stub.advance(0.2)
check("a drag moves the row by what the mouse moved", anchor() == (from.x + 50) .. "," .. (from.y - 30))
check("a drag selects nothing", stub.selected == nil)
check("a drag leaves no tap running", running() == 0)

-- A press whose release Hammerspoon missed does not leave a tap moving the row later.
local moved = anchor()
press()
press()
stub.selected = nil
release()
stub.advance(0.2)
check("only the last press is followed: no tap left running", running() == 0)
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

-- Cursor says nothing when it quits: its chat rabbit leaves once the app is gone.
stub.quitApps = { ["com.todesktop.230313mzl4w4u92"] = true }
stub.advance(10)
check("Cursor's chat rabbit leaves when Cursor quits", not (P.stage.puppets.chat1 and P.stage.puppets.chat1.canvas:isShowing()))
check("the iTerm puppet stays when Cursor quits", P.stage.puppets.tab1 ~= nil and P.stage.puppets.tab1.canvas:isShowing())

-- A puppet whose session has a plan: a click opens the plan card instead, and its button goes to the terminal.
local plansDir = os.tmpname()
os.remove(plansDir)
os.execute("mkdir -p '" .. plansDir .. "'")
P.plansDir = plansDir
local planFile = io.open(plansDir .. "/tab1.json", "w")
planFile:write('{"steps": [{"id": "1", "title": "Fixed the typo.", "status": "active"}], "plan": {"markdown": "# Plan"}}')
planFile:close()
write("PreToolUse|tab1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
f = P.stage.puppets.tab1.canvas:frame()
stub.selected = nil
press()
release()
stub.advance(0.2)
local card = stub.webviews[#stub.webviews]
check("a click on a puppet with a plan opens its card", card ~= nil and card.shown)
check("the card shows the plan", card and card.html_:find("Fixed the typo.", 1, true) ~= nil)
check("the card's click selects no tab", stub.selected == nil)
check("the card sits on the screen", card and card.frame_.x >= 0 and card.frame_.y >= 0
  and card.frame_.x + card.frame_.w <= 1440 and card.frame_.y + card.frame_.h <= 900)
card.content.callback({ body = "focus" })
check("the card hides at once", not card.shown)
check("but is not deleted inside its own callback", not card.deleted)
stub.advance(0.2)
check("the card's Go to terminal selects the tab", stub.selected == "/dev/ttys001")
check("and the card is deleted once its callback is over", card.deleted)

press()
release()
stub.advance(0.2)
local second = stub.webviews[#stub.webviews]
second.content.callback({ body = "close" })
check("Close closes the card", not second.shown and not second.deleted and not P.planCard:isShown())
stub.advance(0.2)
check("and deletes it after", second.deleted)

-- An empty plan has nothing to read: the click goes to the terminal as before.
planFile = io.open(plansDir .. "/tab1.json", "w")
planFile:write('{"steps": []}')
planFile:close()
write("PreToolUse|tab1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
local views = #stub.webviews
stub.selected = nil
press()
release()
stub.advance(0.2)
check("an empty plan: the click selects the tab", stub.selected == "/dev/ttys001")
check("an empty plan: no card", #stub.webviews == views)
os.execute("rm -rf '" .. plansDir .. "'")

os.remove(eventsFile)
check.done("click")
