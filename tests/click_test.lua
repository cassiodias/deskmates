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
  if path:find("git", 1, true) then return nil end
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
local function answer(from, outputs)
  local i = from + 1
  for k = 1, 4 do
    stub.finishTask(i, 0, outputs[k], "")
    i = #stub.tasks
  end
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
writeGitFacts(2, '[{"at": 1400, "commits": [], "endAt": 1500, "files": [], "head": "' .. BASE .. '", "tests": '
  .. '{"failed": 0, "passed": 0, "ran": 0}}, ' .. TURN1 .. "]")
tasks = #stub.tasks
write("Stop|git1||||Done.|my-app|iTerm.app|facts|/dev/ttys009|claude|")
stub.advance(0.2)
check("a facts line redraws with the git answer kept", draws == 1 and gitCard.html_:find("No files edited.", 1, true) ~= nil
  and gitCard.html_:find("1 commit, 1 not committed.", 1, true) ~= nil)
check("a facts line reads git again", #stub.tasks == tasks + 1 and stub.tasks[tasks + 1].args[3] == "rev-list")
draws = 0
answer(tasks, ANSWER)
check("the same answer again does not redraw", draws == 0)
tasks = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
draws = 0
answer(tasks, { "2\n", "M\0src/app.js\0", "src/app.js\0", "" })
check("a new answer redraws", draws == 1 and gitCard.html_:find("2 commits, 1 not committed.", 1, true) ~= nil)
-- Two reads at once: the older one answering last does not undo the newer.
local older = #stub.tasks
write("PreToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
local newer = #stub.tasks
write("PostToolUse|git1||Bash|||my-app|iTerm.app|test|/dev/ttys009|claude|")
stub.advance(0.2)
answer(newer, { "3\n", "M\0src/app.js\0", "", "" })
answer(older, ANSWER)
check("an older read answering last is dropped", gitCard.html_:find("3 commits, 0 not committed.", 1, true) ~= nil)
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
closeCard(closed)
answer(tasks, ANSWER)
check("a card closed before git answers: no update", closed.html_:find("Reading git…", 1, true) ~= nil)
tasks = #stub.tasks
local left = doubleClickOn("git1")
writeFacts("Fixed the typo.")
write("PreToolUse|tab1||Skill||my-developer|app|iTerm.app|facts|/dev/ttys001|claude|")
stub.advance(0.2)
local other = doubleClickOn("tab1")
check("a session with no git opens as today: no git read", #stub.tasks == tasks + 1
  and other.html_:find("ABC-12", 1, true) ~= nil and not other.html_:find('class="actual"', 1, true))
local otherPage = other.html_
answer(tasks, ANSWER)
check("git's late answer leaves another session's card alone", other.html_ == otherPage and left.html_:find("Reading git…", 1, true) ~= nil)
closeCard(other)
hs.fs.attributes = attributes
os.execute("rm -rf '" .. plansDir .. "' '" .. factsDir .. "'")

os.remove(eventsFile)
check.done("click")
