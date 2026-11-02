-- Which animation each command shows, and what the main conversation shows for every other turn.

local Mapping = {}
Mapping.__index = Mapping

-- The animations a list of commands can map to, in menu order.
Mapping.SCENES = { { "coder", "Coder" }, { "matrix", "Matrix" }, { "pingpong", "Ping pong" } }
Mapping.CONVERSATION_CHOICES = {
  { "coder", "Coder" }, { "matrix", "Matrix" }, { "auto", "Ping pong while subagents run, else coder" },
  { "off", "Off" },
}

local function contains(commands, command)
  for _, listed in ipairs(commands) do
    if listed == command then return true end
  end
  return false
end

-- Commands as typed in the menu: comma or space separated, slash optional.
local function parseCommands(typed)
  local commands = {}
  for name in (typed or ""):gmatch("[^,%s]+") do
    name = name:gsub("^/", "")
    if name ~= "" and not contains(commands, name) then commands[#commands + 1] = name end
  end
  return commands
end

-- lists: coder, matrix, pingpong (lists of commands) and conversation ("coder", "matrix", "auto" or "off").
function Mapping.new(lists)
  return setmetatable({
    coder = lists.coder or {}, matrix = lists.matrix or {}, pingpong = lists.pingpong or {},
    conversation = lists.conversation or "auto",
  }, Mapping)
end

-- A choice saved by the menu; one saved by an older version (a commands list with a scene per command)
-- is carried over.
function Mapping.fromSaved(saved, legacyCommands, legacyScenes)
  if saved then return Mapping.new(saved) end
  if not legacyCommands then return nil end
  local lists = { coder = {}, matrix = {}, pingpong = {}, conversation = #legacyCommands == 0 and "auto" or "off" }
  for _, command in ipairs(legacyCommands) do
    local list = (legacyScenes or {})[command] == "pingpong" and lists.pingpong or lists.coder
    list[#list + 1] = command
  end
  return Mapping.new(lists)
end

function Mapping:toSaved()
  return { coder = self.coder, matrix = self.matrix, pingpong = self.pingpong, conversation = self.conversation }
end

-- The animation a command is listed under, if any.
function Mapping:mappedScene(command)
  for _, scene in ipairs(Mapping.SCENES) do
    if command and contains(self[scene[1]], command) then return scene[1] end
  end
end

-- What a turn's command shows: its list's animation, or the main conversation's choice for anything else.
function Mapping:choiceFor(command)
  return self:mappedScene(command) or self.conversation
end

-- Sets one animation's commands from typed text; a command moves out of the other animations' lists.
function Mapping:setList(scene, typed)
  self[scene] = parseCommands(typed)
  for _, other in ipairs(Mapping.SCENES) do
    if other[1] ~= scene then
      local kept = {}
      for _, command in ipairs(self[other[1]]) do
        if not contains(self[scene], command) then kept[#kept + 1] = command end
      end
      self[other[1]] = kept
    end
  end
end

return Mapping
