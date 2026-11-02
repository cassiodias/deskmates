-- Follows the events file: reads the lines appended since the last read; a file that shrank was emptied by
-- the hook, so it starts over from the top.

local Reader = {}
Reader.__index = Reader

function Reader.new(path)
  return setmetatable({ path = path, offset = 0 }, Reader)
end

function Reader:size()
  local file = io.open(self.path, "r")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size
end

-- Calls onLine with each complete new line.
function Reader:read(onLine)
  local size = self:size()
  if not size or size == self.offset then return end
  if size < self.offset then self.offset = 0 end
  local file = io.open(self.path, "r")
  if not file then return end
  file:seek("set", self.offset)
  local data = file:read("a") or ""
  file:close()
  local complete = data:match("^(.*\n)") or ""
  self.offset = self.offset + #complete
  for line in complete:gmatch("([^\n]*)\n") do onLine(line) end
end

return Reader
