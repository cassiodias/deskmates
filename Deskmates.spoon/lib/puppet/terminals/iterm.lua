-- iTerm2: which window and tab holds each terminal device, and selecting one. Asked only while iTerm runs,
-- so it is never launched.

local ITERM = "com.googlecode.iterm2"

local Iterm = {}
Iterm.__index = Iterm

function Iterm.new()
  return setmetatable({ tabs = {}, windows = 0 }, Iterm)
end

-- Refreshes the tab map; true when iTerm answered, so a missing tab really is closed.
function Iterm:refresh()
  self.tabs, self.windows = {}, 0
  if not hs.application.get(ITERM) then return false end
  local ok, result = hs.osascript.applescript([[
    set out to ""
    tell application id "com.googlecode.iterm2"
      set wi to 0
      repeat with w in windows
        set wi to wi + 1
        set ti to 0
        repeat with t in tabs of w
          set ti to ti + 1
          repeat with s in sessions of t
            set out to out & (tty of s) & "=" & wi & "/" & ti & ";"
          end repeat
        end repeat
      end repeat
    end tell
    return out]])
  if not ok or type(result) ~= "string" then return false end
  for tty, window, tab in result:gmatch("([^=;]+)=(%d+)/(%d+);") do
    self.tabs[tty] = { window = tonumber(window), tab = tonumber(tab) }
    self.windows = math.max(self.windows, tonumber(window))
  end
  return true
end

-- The tab a terminal device is in, as shown under a puppet's table; the window too when iTerm has several.
function Iterm:label(tty)
  local place = tty and self.tabs[tty]
  if not place then return nil end
  if self.windows > 1 then return "window " .. place.window .. " · tab " .. place.tab end
  return "tab " .. place.tab
end

-- Selects the window, tab and pane running a terminal device; false when iTerm has none.
function Iterm:select(tty)
  local ok, found = hs.osascript.applescript(string.format([[
    tell application id "com.googlecode.iterm2"
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            if tty of s is "%s" then
              select w
              select t
              select s
              activate
              return true
            end if
          end repeat
        end repeat
      end repeat
    end tell
    return false]], tty))
  return ok and found == true
end

return Iterm
