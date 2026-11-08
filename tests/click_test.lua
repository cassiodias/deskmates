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
stub.itermRunning = true
write("UserPromptSubmit|tab1||||/dev-skill|app|iTerm.app||/dev/ttys001|claude|")
stub.advance(0.2)

local canvas = P.stage.puppets.tab1.canvas
local f = canvas:frame()
local function anchor() return P.stage.anchor.x .. "," .. P.stage.anchor.y end
-- The press and release as the canvas reports them (the press's position deliberately wrong: nothing may
-- depend on it). The mouse tap the press starts may come too late to see the release of a quick click.
local function press() canvas.onMouse(canvas, "mouseDown", nil, 9999, -9999) end
local function release() canvas.onMouse(canvas, "mouseUp", nil, 9999, -9999) end
-- Cassio (5 Nov): one click goes to the terminal, always; a second click within the double-click interval opens
-- the card. Clicks in the tests come a second apart unless they mean a double click.
local function click() press() release() end
local function doubleClick()
  stub.advance(1)
  click()
  stub.advance(0.1)
  click()
end
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
-- Live (6 Nov): hs.window.get asks every app about its windows; once a card had been shown, asking Hammerspoon
-- about its own took 1.6 s a click: the Mac stalled and the double click's second click came too late.
check("one click asks only iTerm about its windows", (stub.windowGets or 0) == 0)
-- Live (5 Nov): AppleScript's `w` is "window N", and selecting a tab reorders iTerm's windows, so `id of w` read
-- after it named another window; and iTerm, once active, raised its own front window over ours.
local script = stub.selectScript or ""
local idAt, selectAt = script:find("set wid to id of w", 1, true), script:find("select t", 1, true)
check("the window's id is read before anything is selected", idAt ~= nil and selectAt ~= nil and idAt < selectAt)
check("the tab's window becomes iTerm's front window", script:find("select (first window whose id is wid)", 1, true) ~= nil
  and script:find("return wid", 1, true) ~= nil)
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
local before_views = #stub.webviews
stub.advance(1)
stub.selected = nil
click()
stub.advance(0.2)
check("one click on a puppet with a plan goes to its terminal", stub.selected == "/dev/ttys001")
check("one click opens no card", #stub.webviews == before_views)
stub.advance(1)
click()
stub.advance(0.2)
check("two clicks a second apart are two single clicks: no card", #stub.webviews == before_views)
stub.selected = nil
doubleClick()
stub.advance(0.2)
local card = stub.webviews[#stub.webviews]
check("a double click on a puppet with a plan opens its card", card ~= nil and card.shown)
check("its first click went to the terminal", stub.selected == "/dev/ttys001")
stub.selected = nil
-- Live: looking up the card's window took 1.5 s, and a card left inactive behind the terminal lost its first
-- click and hid itself a second later. Hammerspoon is made the active app instead.
check("the card makes Hammerspoon the active app", (stub.activated or 0) >= 1)
check("the card never looks up its window", (stub.windowLookups or 0) == 0)
check("the card shows the plan", card and card.html_:find("Fixed the typo.", 1, true) ~= nil)
check("the second click selects no tab again", stub.selected == nil)
check("the card sits on the screen", card and card.frame_.x >= 0 and card.frame_.y >= 0
  and card.frame_.x + card.frame_.w <= 1440 and card.frame_.y + card.frame_.h <= 900)
-- Live (6 Nov): the first click brings the terminal forward, and it became the active app a moment after the card
-- showed: the card lost the focus and hid itself, before anything could be read. It opens beside the terminal and
-- stays there until it is closed.
card.windowCallback_("focusChange", card, false)
check("the terminal coming forward after a double click does not hide the card", card.shown and P.planCard:isShown())
card.content.callback({ body = "focus" })
stub.advance(0.2)
check("the card's Go to terminal selects the tab", stub.selected == "/dev/ttys001")
-- Cassio (5 Nov): the card stays beside the terminal; losing the focus to it does not hide the card.
check("Go to terminal leaves the card open", card.shown and not card.deleted and P.planCard:isShown())
card.windowCallback_("focusChange", card, false)
check("and the terminal taking the focus does not hide it", card.shown and P.planCard:isShown())
card.content.callback({ body = "close" })
stub.advance(0.2)
check("Close still closes it", not card.shown and card.deleted)

-- Live (6 Nov): when going to the terminal was slow, the second click waited behind it and was judged a second
-- single click. The double click's gap is counted from when the first click was done.
stub.selectSeconds = 1.6
local slowViews = #stub.webviews
doubleClick()
stub.advance(0.2)
stub.selectSeconds = nil
check("a double click opens the card when the first click was slow", #stub.webviews > slowViews
  and stub.webviews[#stub.webviews].shown)
stub.webviews[#stub.webviews].content.callback({ body = "close" })
stub.advance(0.2)

doubleClick()
stub.advance(0.2)
local second = stub.webviews[#stub.webviews]
second.content.callback({ body = "close" })
check("Close closes the card", not second.shown and not second.deleted and not P.planCard:isShown())
stub.advance(0.2)
check("and deletes it after", second.deleted)

-- The card can be resized, and the next one opens at the size it was left.
local function openCard()
  doubleClick()
  stub.advance(0.2)
  return stub.webviews[#stub.webviews]
end
local function closeCard(view)
  view.content.callback({ body = "close" })
  stub.advance(0.2)
end
local resized = openCard()
local resizable = false
for _, style in ipairs(resized.style_ or {}) do if style == "resizable" then resizable = true end end
check("the card can be resized", resizable)
resized.windowCallback_("frameChange", resized, { x = 0, y = 0, w = 650, h = 500 })
local saved = stub.settings["Deskmates.cardSize"]
check("a new size is remembered", type(saved) == "table" and saved.w == 650 and saved.h == 500)
closeCard(resized)
local again = openCard()
check("the next card opens at it", again.frame_.w == 650 and again.frame_.h == 500)
closeCard(again)
stub.settings["Deskmates.cardSize"] = { w = 5000, h = 5000 }
local huge = openCard()
check("a size bigger than the screen fits on it", huge.frame_.w == 1440 and huge.frame_.h == 900
  and huge.frame_.x == 0 and huge.frame_.y == 0)
closeCard(huge)
stub.settings["Deskmates.cardSize"] = "big"
local junk = openCard()
check("a junk size gives the default", junk.frame_.w == 600 and junk.frame_.h == 560)
closeCard(junk)

-- Hammerspoon reports the window's frame, title bar included, as soon as the card shows: opening the card
-- again and again must not make it grow.
stub.titleBar = 19
stub.settings["Deskmates.cardSize"] = { w = 700, h = 500 }
for _ = 1, 3 do
  local view = openCard()
  view.windowCallback_("frameChange", view, view:frame())
  closeCard(view)
end
local kept = stub.settings["Deskmates.cardSize"]
check("reopening the card does not make it grow", kept.w == 700 and kept.h == 500)
local grown = openCard()
grown.windowCallback_("frameChange", grown, { x = 0, y = 0, w = 800, h = 619 })
check("a resize saves the card's own size, not its window's", stub.settings["Deskmates.cardSize"].h == 600)
closeCard(grown)
stub.titleBar = 0

-- An empty plan has nothing to read: the click goes to the terminal as before.
planFile = io.open(plansDir .. "/tab1.json", "w")
planFile:write('{"steps": []}')
planFile:close()
write("PreToolUse|tab1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
local views = #stub.webviews
stub.selected = nil
doubleClick()
stub.advance(0.2)
check("an empty plan: a double click selects the tab", stub.selected == "/dev/ttys001")
check("an empty plan: no card", #stub.webviews == views)

-- Facts: a session with facts opens the card too, with its ticket; a facts line refreshes an open card.
local factsDir = os.tmpname()
os.remove(factsDir)
os.execute("mkdir -p '" .. factsDir .. "'")
P.factsDir = factsDir
local factsWritten = 0
local function writeFacts(reply)
  factsWritten = factsWritten + 1
  local file = io.open(factsDir .. "/tab1.json", "w")
  file:write('{"updatedAt": ' .. factsWritten .. ', "current": "ABC-12", "tickets": {"ABC-12": {"phase": "dev", "phaseAt": 1, "phases": {"dev": 1}, "seen": 2}},'
    .. ' "timeline": [{"at": 2, "ticket": "ABC-12", "kind": "reply", "text": "' .. reply .. '", "phase": "dev"}]}')
  file:close()
end
writeFacts("Fixed the typo.")
write("PreToolUse|tab1||Skill||my-developer|app|iTerm.app|facts|/dev/ttys001|claude|")
stub.advance(0.2)
stub.selected = nil
local factsCard = openCard()
check("facts only: a double click opens the card", factsCard and factsCard.shown and #stub.webviews == views + 1)
check("facts only: with the ticket", factsCard.html_:find("ABC-12", 1, true) ~= nil)
check("facts only: its first click selected the tab", stub.selected == "/dev/ttys001")
writeFacts("Built and committed.")
write("Stop|tab1||||Built and committed.|app|iTerm.app|facts|/dev/ttys001|claude|")
stub.advance(0.2)
check("a facts line refreshes the open card", factsCard.html_:find("Built and committed.", 1, true) ~= nil
  and #stub.webviews == views + 1 and factsCard.shown)
factsCard.html_ = "unchanged"
write("PreToolUse|tab1||Bash|||app|iTerm.app|test|/dev/ttys001|claude|")
write("PostToolUse|tab1||Bash|||app|iTerm.app|test|/dev/ttys001|claude|")
stub.advance(0.2)
check("a line that changed nothing leaves the open card as it was (its scroll too)", factsCard.html_ == "unchanged")
closeCard(factsCard)

-- Cassio (6 Nov): the card opens on the step happening now; a step the reader picks (or none) is drawn picked again
-- when the card is drawn again; a step gone since, or a junk message, gives the step happening now.
local function writeSteps(n)
  factsWritten = factsWritten + 1
  local file = io.open(factsDir .. "/tab1.json", "w")
  file:write('{"updatedAt": ' .. factsWritten .. ', "current": "ABC-12", "tickets": {"ABC-12": {"phase": "dev", "phaseAt": 2, '
    .. '"seen": 3, "passes": [{"phase": "plan", "at": 1, "endAt": 2}, {"phase": "dev", "at": 2}]}}, "timeline": [{"at": 3, '
    .. '"ticket": "ABC-12", "kind": "reply", "text": "Step ' .. n .. '.", "phase": "dev"}]}')
  file:close()
  write("Stop|tab1||||Done.|app|iTerm.app|facts|/dev/ttys001|claude|")
  stub.advance(0.2)
end
local DEV_ON, PLAN_ON = 'class="phase current on" data-phase="dev"', 'class="phase done on" data-phase="plan"'
writeSteps(1)
local stepCard = openCard()
check("steps: the step happening now is picked", stepCard.html_:find(DEV_ON, 1, true) ~= nil)
stepCard.content.callback({ body = "step:1" })
writeSteps(2)
check("steps: the reader's step drawn picked again", stepCard.html_:find("Step 2.", 1, true) ~= nil
  and stepCard.html_:find(PLAN_ON, 1, true) ~= nil and not stepCard.html_:find(DEV_ON, 1, true))
for _, junk in ipairs({ "step:2x", "step:-2", "step: 2", "step:", "step:None", 42 }) do
  stepCard.content.callback({ body = junk })
end
writeSteps(3)
check("steps: junk messages change nothing", stepCard.html_:find("Step 3.", 1, true) ~= nil
  and stepCard.html_:find(PLAN_ON, 1, true) ~= nil)
stepCard.content.callback({ body = "step:none" })
writeSteps(4)
check("steps: none picked stays none", stepCard.html_:find("Step 4.", 1, true) ~= nil
  and not stepCard.html_:find(PLAN_ON, 1, true) and not stepCard.html_:find(DEV_ON, 1, true))
stepCard.content.callback({ body = "step:99" })
writeSteps(5)
check("steps: a step gone since gives the step happening now", stepCard.html_:find("Step 5.", 1, true) ~= nil
  and stepCard.html_:find(DEV_ON, 1, true) ~= nil)
closeCard(stepCard)

planFile = io.open(plansDir .. "/tab1.json", "w")
planFile:write('{"steps": [{"id": "1", "title": "Write the failing test", "status": "active"}]}')
planFile:close()
write("PreToolUse|tab1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
stub.advance(0.2)
local bothCard = openCard()
check("plan and facts: one card with both", bothCard.html_:find("ABC-12", 1, true) ~= nil
  and bothCard.html_:find("Write the failing test", 1, true) ~= nil)
closeCard(bothCard)

planFile = io.open(plansDir .. "/tab1.json", "w")
planFile:write('{"steps": []}')
planFile:close()
write("PreToolUse|tab1||TodoWrite|||app|iTerm.app|plan|/dev/ttys001|claude|")
local junkFacts = io.open(factsDir .. "/tab1.json", "w")
junkFacts:write('{"tickets": {')
junkFacts:close()
write("Stop|tab1||||Done.|app|iTerm.app|facts|/dev/ttys001|claude|")
stub.advance(0.2)
views = #stub.webviews
stub.selected = nil
doubleClick()
stub.advance(0.2)
check("junk facts and no plan: a double click selects the tab", stub.selected == "/dev/ttys001" and #stub.webviews == views)

-- Plan vs actual: a session in a git repo opens its card at once, reading git, and git's answer fills it.
-- git is found at /opt/homebrew/bin/git whatever this machine has; its commands are the stub's tasks.
local attributes = hs.fs.attributes
hs.fs.attributes = function(path, field)
  if path == "/opt/homebrew/bin/git" then return { mode = "file" } end
  -- No other git (the facts of session git1 are a file like any other).
  if path:match("/git$") then return nil end
  -- No gh in this part, whatever this machine has (the PR's own part below has one).
  if path:match("/gh$") then return nil end
  return attributes(path, field)
end
local REPO, BASE = "/Users/me/my-app", "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
-- The facts as the hooks write them (harnesses/claude/fixtures/actual-stop.facts), with updatedAt `n` and the
-- turns given as JSON.
local function writeGitFacts(n, turnsJson)
  local file = io.open(factsDir .. "/git1.json", "w")
  file:write('{"git": {"base": "' .. BASE .. '", "dirtyAtStart": [], "folder": "' .. REPO .. '", "prefix": "", "root": "'
    .. REPO .. '", "top": null}, "seen": {"src/app.js": true}, "tickets": {}, "timeline": [], "turns": ' .. turnsJson
    .. ', "updatedAt": ' .. n .. '}')
  file:close()
end
local TURN1 = '{"at": 1000, "commits": [{"hash": "e4f5a6b", "subject": "Fixed the typo."}], "endAt": 1300, "files": '
  .. '["src/app.js"], "head": "' .. BASE .. '", "tests": {"failed": 0, "passed": 2, "ran": 2}}'
os.execute("mkdir -p '" .. factsDir .. "'")
write("UserPromptSubmit|git1||||Fix it|my-app|iTerm.app||/dev/ttys009|claude|")
write("Stop|git1||||Done.|my-app|iTerm.app||/dev/ttys009|claude|")
stub.advance(0.2)
-- Written with no facts line after it: the double click reads the file again itself.
writeGitFacts(1, "[" .. TURN1 .. "]")
local function doubleClickOn(key)
  local c = P.stage.puppets[key].canvas
  local function once()
    c.onMouse(c, "mouseDown", nil, 0, 0)
    c.onMouse(c, "mouseUp", nil, 0, 0)
  end
  stub.advance(1)
  once()
  stub.advance(0.1)
  once()
  stub.advance(0.2)
  return stub.webviews[#stub.webviews]
end
-- Answers the git read whose first command is task `from` + 1; each next command is the newest task.
local ANSWER = { "1\n", "M\0src/app.js\0", "", "scratch.sh\0" }
-- A session with commits in its turns gets a fifth command (the files of its own commits): answered with
-- outputs[5], or nothing.
local function answer(from, outputs)
  local i = from + 1
  for k = 1, 4 do
    stub.finishTask(i, 0, outputs[k], "")
    i = #stub.tasks
  end
  if i > from + 4 and not stub.tasks[i].finished then stub.finishTask(i, 0, outputs[5] or "", "") end
end

local tasks = #stub.tasks
views = #stub.webviews
local gitCard = doubleClickOn("git1")
check("git only: a double click opens the card", #stub.webviews == views + 1 and gitCard.shown)
check("git only: reading git at once", gitCard.html_:find("Reading git…", 1, true) ~= nil)
check("git only: the turns at once, from the facts file", gitCard.html_:find("Fixed the typo.", 1, true) ~= nil
  and gitCard.html_:find("tests passed (2 of 2)", 1, true) ~= nil)
local first = stub.tasks[tasks + 1]
check("git only: git runs in the session's repo", first ~= nil and first.path == "/opt/homebrew/bin/git"
  and first.args[1] == "-C" and first.args[2] == REPO and first.args[3] == "rev-list" and first.started)
answer(tasks, ANSWER)
check("git's answer fills the card", gitCard.html_:find("1 commit, 1 not committed.", 1, true) ~= nil
  and gitCard.html_:find("<li><code>src/app.js</code></li>", 1, true) ~= nil
  and gitCard.html_:find('<li><code>scratch.sh</code> <span class="unseen">no edit seen</span></li>', 1, true) ~= nil
  and not gitCard.html_:find("Reading git…", 1, true))

-- A facts line: the card shows the new facts with the git answer it has, and reads git again.
local draws = 0
local html = gitCard.html
gitCard.html = function(self, page) draws = draws + 1 return html(self, page) end
writeGitFacts(2, '[{"at": 1400, "commits": [], "endAt": 1500, "files": ["src/b.js"], "head": "' .. BASE .. '", "tests": '
  .. '{"failed": 0, "passed": 0, "ran": 0}}, ' .. TURN1 .. "]")
tasks = #stub.tasks
write("Stop|git1||||Done.|my-app|iTerm.app|facts|/dev/ttys009|claude|")
stub.advance(0.2)
check("a facts line redraws with the git answer kept", draws == 1 and gitCard.html_:find("<code>src/b.js</code>", 1, true) ~= nil
  and gitCard.html_:find("1 commit, 1 not committed.", 1, true) ~= nil)
check("a facts line reads git again", #stub.tasks == tasks + 1 and stub.tasks[tasks + 1].args[3] == "rev-list")
draws = 0
answer(tasks, ANSWER)
check("the same answer again does not redraw", draws == 0)
-- An edit mid-turn: the hooks write the facts but flag no line. Any line of the card's session that finds its facts
-- file changed redraws the card and reads git again; a line that finds it the same does neither.
writeGitFacts(3, '[{"at": 1400, "files": ["src/b.js", "src/edited-mid-turn.js"], "head": "' .. BASE .. '", "tests": '
  .. '{"failed": 0, "passed": 0, "ran": 0}}, ' .. TURN1 .. "]")
tasks = #stub.tasks
draws = 0
write("PreToolUse|git1||Edit|||my-app|iTerm.app||/dev/ttys009|claude|")
stub.advance(0.2)
check("an edit mid-turn: the open card shows its file", draws == 1
  and gitCard.html_:find("src/edited-mid-turn.js", 1, true) ~= nil)
check("an edit mid-turn: git read again", #stub.tasks == tasks + 1 and stub.tasks[tasks + 1].args[3] == "rev-list")
answer(tasks, ANSWER)
tasks = #stub.tasks
draws = 0
write("PostToolUse|git1||Edit|||my-app|iTerm.app||/dev/ttys009|claude|")
stub.advance(0.2)
check("facts unchanged: no redraw, no git", draws == 0 and #stub.tasks == tasks)
tasks = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
draws = 0
answer(tasks, { "2\n", "M\0src/app.js\0", "src/app.js\0", "" })
check("a new answer redraws", draws == 1 and gitCard.html_:find("2 commits, 1 not committed.", 1, true) ~= nil)
-- One read at a time (five commands: this session has commits of its own): lines while git reads start none; one
-- more read follows it, and shows the newest state.
local inFlight = #stub.tasks
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
check("one read at a time: lines meanwhile start no git", #stub.tasks == inFlight + 1)
answer(inFlight, ANSWER)
local again = #stub.tasks
check("one read at a time: one more read after it", again == inFlight + 6 and stub.tasks[again].args[3] == "rev-list")
answer(again - 1, { "3\n", "M\0src/app.js\0", "", "" })
check("one read at a time: the read after shows the newest", gitCard.html_:find("3 commits, 0 not committed.", 1, true) ~= nil)
check("one read at a time: then nothing more", #stub.tasks == again + 4)
-- A read that fails still lets the one waiting run.
local failing = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
stub.finishTask(failing + 1, 128, "", "fatal: something")
check("a failed read: the one waiting runs", #stub.tasks == failing + 2 and stub.tasks[failing + 2].args[3] == "rev-list")
answer(failing + 1, { "3\n", "M\0src/app.js\0", "", "" })
-- A panel folded on the page stays folded when the card is drawn again; junk fold messages change nothing.
local TURNS_OPEN, TURNS_FOLDED = '<details class="panel story" data-panel="story" open>', '<details class="panel story" data-panel="story">'
check("panels open at first", gitCard.html_:find(TURNS_OPEN, 1, true) ~= nil)
gitCard.content.callback({ body = "fold:story:closed" })
for _, junk in ipairs({ "fold:turns:closed", "fold:actual:shut", "fold:plan:closed", "fold:actual:closed:x", "fold:ACTUAL:closed", 42 }) do
  gitCard.content.callback({ body = junk })
end
tasks = #stub.tasks
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
answer(tasks, { "4\n", "M\0src/app.js\0", "", "" })
check("a folded panel stays folded on a redraw", gitCard.html_:find("4 commits, 0 not committed.", 1, true) ~= nil
  and gitCard.html_:find(TURNS_FOLDED, 1, true) ~= nil and not gitCard.html_:find(TURNS_OPEN, 1, true))
check("junk fold messages fold nothing", gitCard.html_:find('<details class="panel actual" data-panel="actual" open>', 1, true) ~= nil)
gitCard.content.callback({ body = "fold:story:open" })
tasks = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
answer(tasks, { "5\n", "M\0src/app.js\0", "", "" })
check("opened again, drawn open", gitCard.html_:find(TURNS_OPEN, 1, true) ~= nil)
gitCard.content.callback({ body = "fold:story:closed" })
closeCard(gitCard)

-- git fails, is too slow, or lost the base: one line in the block, the turns still there.
tasks = #stub.tasks
local failed = doubleClickOn("git1")
stub.finishTask(tasks + 1, 128, "", "fatal: not a git repository")
check("a failing git: git did not answer", failed.html_:find('<p class="line">git did not answer</p>', 1, true) ~= nil
  and failed.html_:find("Fixed the typo.", 1, true) ~= nil)
check("a failing git: no command after it", #stub.tasks == tasks + 1)
closeCard(failed)
tasks = #stub.tasks
local slow = doubleClickOn("git1")
stub.advance(3)
check("a slow git: git did not answer, and it is stopped", slow.html_:find("git did not answer", 1, true) ~= nil
  and stub.tasks[tasks + 1].terminated)
closeCard(slow)
tasks = #stub.tasks
local gone = doubleClickOn("git1")
stub.finishTask(tasks + 1, 128, "", "fatal: bad revision 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678..HEAD'")
check("a base gone: says so", gone.html_:find("base a1b2c3d no longer exists", 1, true) ~= nil)
closeCard(gone)

-- A card closed before git answers gets nothing; nor does another session's card opened since.
tasks = #stub.tasks
local closed = doubleClickOn("git1")
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
closeCard(closed)
answer(tasks, ANSWER)
check("a card closed before git answers: no update", closed.html_:find("Reading git…", 1, true) ~= nil)
check("a card closed before git answers: the read waiting is dropped", #stub.tasks == tasks + 5)
tasks = #stub.tasks
local left = doubleClickOn("git1")
writeFacts("Fixed the typo.")
write("PreToolUse|tab1||Skill||my-developer|app|iTerm.app|facts|/dev/ttys001|claude|")
stub.advance(0.2)
local other = doubleClickOn("tab1")
check("a session with no git opens as today: no git read", #stub.tasks == tasks + 1
  and other.html_:find("ABC-12", 1, true) ~= nil and not other.html_:find('data-panel="actual"', 1, true))
local otherPage = other.html_
answer(tasks, ANSWER)
check("git's late answer leaves another session's card alone", other.html_ == otherPage and left.html_:find("Reading git…", 1, true) ~= nil)
closeCard(other)
-- Another session's card opened since: the folds were that session's, so this one opens with every panel open.
tasks = #stub.tasks
local reopened = doubleClickOn("git1")
answer(tasks, ANSWER)
check("another session's card opened since: all open", reopened.html_:find(TURNS_OPEN, 1, true) ~= nil)
closeCard(reopened)

-- The PR: with gh there, the card also asks gh, in the repo, beside git; its answer is one line under what
-- changed. A busy session's lines do not ask GitHub again within config.PR_EVERY.
local withoutGh = hs.fs.attributes
hs.fs.attributes = function(path, field)
  if path == "/opt/homebrew/bin/gh" then return { mode = "file" } end
  return withoutGh(path, field)
end
local MERGED = '{"number":5,"state":"MERGED","isDraft":false,"url":"https://github.com/me/my-app/pull/5","statusCheckRollup":[]}'
local function ghTasks(from)
  local out = {}
  for i = from + 1, #stub.tasks do
    if stub.tasks[i].path == "/opt/homebrew/bin/gh" then out[#out + 1] = i end
  end
  return out
end
tasks = #stub.tasks
local prCard = doubleClickOn("git1")
local gh = ghTasks(tasks)
check("PR: one gh read on open", #gh == 1 and stub.tasks[gh[1]].cwd == REPO and stub.tasks[gh[1]].args[1] == "pr"
  and stub.tasks[gh[1]].args[2] == "view")
check("PR: git starts first", stub.tasks[tasks + 1].path == "/opt/homebrew/bin/git")
-- The git read: its commands are the tasks after the gh one.
local i = tasks + 1
for k = 1, 4 do
  stub.finishTask(i, 0, ANSWER[k], "")
  i = #stub.tasks
end
if not stub.tasks[i].finished then stub.finishTask(i, 0, "", "") end
check("PR: no line before gh answers", not prCard.html_:find('class="pr"', 1, true))
stub.finishTask(gh[1], 0, MERGED, "")
check("PR: its line on the card, a button to its page", prCard.html_:find('<button class="pr-open"', 1, true) ~= nil
  and prCard.html_:find(">PR #5 · merged</button>", 1, true) ~= nil
  and prCard.html_:find("1 commit, 1 not committed.", 1, true) ~= nil)
prCard.content.callback({ body = "open:pr" })
check("PR: a click opens its page in the browser", stub.openedURLs[#stub.openedURLs] == "https://github.com/me/my-app/pull/5")
local opened = #stub.openedURLs
for _, junk in ipairs({ "open:PR", "open:pr:x", "open:https://evil.example", 7 }) do prCard.content.callback({ body = junk }) end
check("PR: other messages open nothing", #stub.openedURLs == opened)
local before = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
check("PR: a facts line soon after asks no gh", #ghTasks(before) == 0)
answer(before, ANSWER)
stub.advance(61)
before = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
gh = ghTasks(before)
check("PR: a minute later, one more gh read", #gh == 1)
answer(before, ANSWER)
stub.finishTask(gh[1], 1, "", "no pull requests found")
check("PR: none any more, no line, the rest as before", not prCard.html_:find('class="pr"', 1, true)
  and prCard.html_:find("1 commit, 1 not committed.", 1, true) ~= nil)
closeCard(prCard)
-- A card closed before gh answers gets nothing.
tasks = #stub.tasks
local closedPr = doubleClickOn("git1")
gh = ghTasks(tasks)
answer(tasks, ANSWER)
local closedPage = closedPr.html_
closeCard(closedPr)
stub.finishTask(gh[1], 0, MERGED, "")
check("PR: a card closed before gh answers: no update", closedPr.html_ == closedPage)
-- A session with no git asks no gh.
tasks = #stub.tasks
local noGit = doubleClickOn("tab1")
check("PR: a session with no git: no gh", #ghTasks(tasks) == 0)
closeCard(noGit)
hs.fs.attributes = attributes
os.execute("rm -rf '" .. plansDir .. "' '" .. factsDir .. "'")

-- Backfill: a Claude session with no facts, whose transcript is where Claude Code keeps it. Its card opens at once
-- and reads the transcript; the answer fills it.
os.execute("mkdir -p '" .. stub.home .. "/.claude/projects/-work-my-app' '" .. factsDir .. "'")
for _, sid in ipairs({ "bf1", "bf2", "bf3", "cx1" }) do
  io.open(stub.home .. "/.claude/projects/-work-my-app/" .. sid .. ".jsonl", "w"):close()
end
-- Each in a terminal of its own (an iTerm tab): a session working in a terminal closes the others resting there.
stub.tabs = stub.tabs .. "/dev/ttys021=3/1;/dev/ttys022=3/2;/dev/ttys023=3/3;/dev/ttys024=3/4;"
for i, sid in ipairs({ "bf1", "bf2", "bf3" }) do
  write("UserPromptSubmit|" .. sid .. "||||/dev-skill|my-app|iTerm.app||/dev/ttys02" .. i .. "|claude|")
  write("Stop|" .. sid .. "||||Hi.|my-app|iTerm.app||/dev/ttys02" .. i .. "|claude|")
end
write("UserPromptSubmit|cx1||||/dev-skill|my-app|iTerm.app||/dev/ttys024|codex|")
write("Stop|cx1||||Hi.|my-app|iTerm.app||/dev/ttys024|codex|")
stub.advance(0.2)
tasks = #stub.tasks
local views0 = #stub.webviews
local bf = doubleClickOn("bf1")
check("backfill: a card with no facts opens", #stub.webviews == views0 + 1 and bf.shown
  and bf.html_:find("Reading the transcript…", 1, true) ~= nil)
local bfTask = stub.tasks[tasks + 1]
check("backfill: one run of the script, for the session", #stub.tasks == tasks + 1 and bfTask.path == "/bin/sh"
  and bfTask.args[1]:match("/hook/backfill%.sh$") ~= nil and bfTask.args[2] == "bf1")
doubleClickOn("bf1")
check("backfill: one at a time", #stub.tasks == tasks + 1)
local file = io.open(factsDir .. "/bf1.json", "w")
file:write('{"updatedAt": 1, "current": "ABC-12", "tickets": {"ABC-12": {"phase": "dev", "phaseAt": 1, "phases": {"dev": 1}, "seen": 2}},'
  .. ' "timeline": [{"at": 2, "ticket": "ABC-12", "kind": "reply", "text": "Filled from the transcript.", "phase": "dev"}]}')
file:close()
stub.finishTask(tasks + 1, 0, "ok 1\n", "")
local filled = stub.webviews[#stub.webviews]
check("backfill: its answer fills the card", filled.html_:find("Filled from the transcript.", 1, true) ~= nil
  and not filled.html_:find("Reading the transcript…", 1, true))
closeCard(filled)
tasks = #stub.tasks
local failing = doubleClickOn("bf2")
stub.finishTask(tasks + 1, 1, "error transcript not readable\n", "")
check("backfill: an error says so", failing.html_:find("transcript not readable", 1, true) ~= nil)
closeCard(failing)
-- The transcript then vanishes: the old answer is not shown again; with no facts, no card opens.
os.remove(stub.home .. "/.claude/projects/-work-my-app/bf2.jsonl")
tasks = #stub.tasks
views0 = #stub.webviews
doubleClickOn("bf2")
check("backfill: a transcript gone: no old answer, no card", P:backfillState("bf2") == nil and #stub.webviews == views0
  and #stub.tasks == tasks)
tasks = #stub.tasks
local gone = doubleClickOn("bf3")
local page = gone.html_
closeCard(gone)
stub.finishTask(tasks + 1, 0, "ok 1\n", "")
check("backfill: a card closed before the answer gets nothing", gone.html_ == page)
tasks = #stub.tasks
views0 = #stub.webviews
doubleClickOn("cx1")
check("backfill: a Codex session reads none and, with no facts, opens no card", #stub.tasks == tasks
  and #stub.webviews == views0)

os.remove(eventsFile)
check.done("click")
