-- The plan card's blocks: a plan's markdown read into blocks of raw text (headings, paragraphs, lists, code,
-- quotes, tables, rules), and the blocks lifted from them. Nothing here is escaped or drawn: ui/plancard.lua
-- does that. It knows no Hammerspoon.

local planblocks = {}

local function trim(text) return (text:match("^%s*(.-)%s*$")) end

local function isItem(line) return line:match("^%s*[-*+]%s") or line:match("^%s*%d+[.)]%s") end

local function cells(line)
  local out = {}
  line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  for cell in (line .. "|"):gmatch("([^|]*)|") do out[#out + 1] = trim(cell) end
  return out
end

-- Every block is a table with `kind`, its fields, and `source`: its lines as written.
function planblocks.parse(text)
  local blocks, lines, i = {}, {}, 1
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if text == "" then lines = {} end
  local function add(block, first, last)
    block.source = table.concat(lines, "\n", first, math.min(last, #lines))
    blocks[#blocks + 1] = block
  end
  while i <= #lines do
    local line, first = lines[i], i
    if line:match("^%s*```") then
      local code = {}
      local lang = trim(line:match("^%s*```(.*)$"))
      i = i + 1
      while i <= #lines and not lines[i]:match("^%s*```") do code[#code + 1] = lines[i]; i = i + 1 end
      add({ kind = "code", lang = lang, lines = code }, first, i)
      i = i + 1
    elseif line:match("^%s*$") then
      i = i + 1
    elseif line:match("^#+%s") then
      local marks, title = line:match("^(#+)%s+(.-)%s*#*%s*$")
      add({ kind = "heading", level = math.min(#marks, 6), text = title }, i, i)
      i = i + 1
    elseif line:match("^%s*[-*_]%s*[-*_]%s*[-*_][-*_%s]*$") then
      add({ kind = "rule" }, i, i)
      i = i + 1
    elseif line:match("^%s*>") then
      local quote = {}
      while i <= #lines and lines[i]:match("^%s*>") do quote[#quote + 1] = (lines[i]:gsub("^%s*>%s?", "")); i = i + 1 end
      add({ kind = "quote", lines = quote }, first, i - 1)
    elseif line:match("^%s*|") then
      local rows = {}
      while i <= #lines and lines[i]:match("^%s*|") do
        if not lines[i]:match("^[%s|:-]+$") then rows[#rows + 1] = cells(lines[i]) end
        i = i + 1
      end
      add({ kind = "table", rows = rows }, first, i - 1)
    elseif isItem(line) then
      local items = {}
      while i <= #lines and isItem(lines[i]) do
        items[#items + 1] = lines[i]:match("^%s*[-*+]%s+(.*)$") or lines[i]:match("^%s*%d+[.)]%s+(.*)$")
        i = i + 1
      end
      add({ kind = "list", ordered = line:match("^%s*%d") ~= nil, items = items }, first, i - 1)
    else
      local para = {}
      while i <= #lines and not lines[i]:match("^%s*$") and not lines[i]:match("^#+%s") and not lines[i]:match("^%s*```")
        and not isItem(lines[i]) and not lines[i]:match("^%s*[>|]") do
        para[#para + 1] = trim(lines[i])
        i = i + 1
      end
      add({ kind = "paragraph", lines = para }, first, i - 1)
    end
  end
  return blocks
end

local BADGES = {
  new = "new", create = "new", created = "new", add = "new", added = "new",
  edit = "edit", modify = "edit", modified = "edit", change = "edit", changed = "edit", update = "edit", updated = "edit",
  delete = "delete", deleted = "delete", remove = "delete", removed = "delete",
}
local SEPARATORS = { ":", "-", "—", "–", "·", "," }

-- Text with spaces and separators taken off both ends.
local function clean(text)
  local again = true
  while again do
    again = false
    text = trim(text)
    for _, sep in ipairs(SEPARATORS) do
      if text:sub(1, #sep) == sep then text, again = text:sub(#sep + 1), true end
      if #text >= #sep and text:sub(-#sep) == sep then text, again = text:sub(1, -#sep - 1), true end
    end
  end
  return text
end

-- The first code span of text when it names a file (no space; a folder or an extension, maybe with :lines),
-- and the text without it.
local function pathIn(text)
  local s, e, code = text:find("`([^`]+)`")
  if not code or code:find("%s") then return nil end
  local bare = code:gsub(":[%d][%d%-,]*$", "")
  if not (bare:find("/") or bare:find("%.%w+$")) then return nil end
  return code, text:sub(1, s - 1) .. " " .. text:sub(e + 1)
end

-- Whether text starts with a separator standing alone (":", or a dash or dot with a space after it).
local function separated(text)
  text = text:match("^%s*(.*)$")
  if text == "" or text:sub(1, 1) == ":" then return true end
  for _, sep in ipairs({ "—", "–", "-", "·" }) do
    if text:sub(1, #sep) == sep and (#text == #sep or text:sub(#sep + 1, #sep + 1):match("%s")) then return true end
  end
  return false
end

-- A badge from a word in brackets ("(new)"), or from the text's first word when a separator follows it or it
-- stands alone ("Create: …", "new"), and the text without it. "Add a flag" is a sentence, not a badge.
local function badgeIn(text)
  local word, rest = text:match("^%s*(%a+)(.*)$")
  if word and BADGES[word:lower()] and separated(rest) then return BADGES[word:lower()], rest end
  local s, e, inner = text:find("%((%a+)%)")
  if inner and BADGES[inner:lower()] then return BADGES[inner:lower()], text:sub(1, s - 1) .. text:sub(e + 1) end
  return nil, text
end

local function named(text, names)
  text = trim((text or ""):gsub("[%*_]", "")):lower():gsub(":$", "")
  for _, name in ipairs(names) do if text == name or text:sub(1, #name + 1) == name .. " " then return true end end
  return false
end

local FILE_HEADINGS = { "files", "file map" }
local FILE_COLUMNS = { file = true, files = true, path = true, paths = true }

-- A list under a Files heading or a "Files:" line, or a table with a File or Path column, every row naming a
-- file: { kind = "filemap", rows = { { path, badge, note } }, titled, source }. `titled` when a heading or line
-- above already says Files. Nil for anything else.
function planblocks.fileMap(block, context)
  local rows = {}
  if block.kind == "list" then
    local before = context.before
    local marked = before and before.kind == "paragraph" and #before.lines == 1
      and named(before.lines[1], { "files" }) and trim(before.lines[1]):match(":%**$") ~= nil
    local titled = marked or (context.heading and named(context.heading.text, FILE_HEADINGS))
    if not titled then return nil end
    for _, item in ipairs(block.items) do
      local path, rest = pathIn(item)
      if not path then return nil end
      local badge
      badge, rest = badgeIn(rest)
      rows[#rows + 1] = { path = path, badge = badge, note = clean(rest) }
    end
    return { kind = "filemap", rows = rows, titled = true, source = block.source }
  elseif block.kind == "table" and #block.rows >= 2 then
    local column
    for c, cell in ipairs(block.rows[1]) do
      if FILE_COLUMNS[trim(cell:gsub("[%*_`]", "")):lower()] then column = c break end
    end
    if not column then return nil end
    for r = 2, #block.rows do
      local path, left = pathIn(block.rows[r][column] or "")
      if not path then return nil end
      -- The file's cell holds its path and at most a badge: anything more would be lost from the row.
      local badge, notes = badgeIn(left)
      if clean(notes) ~= "" then return nil end
      notes = {}
      for c, cell in ipairs(block.rows[r]) do
        if c ~= column then
          if not badge then
            local found, rest = badgeIn(cell)
            if found then badge, cell = found, rest end
          end
          cell = clean(cell)
          if cell ~= "" then notes[#notes + 1] = cell end
        end
      end
      rows[#rows + 1] = { path = path, badge = badge, note = table.concat(notes, " · ") }
    end
    local titled = context.heading ~= nil and named(context.heading.text, FILE_HEADINGS)
    return { kind = "filemap", rows = rows, titled = titled, source = block.source }
  end
  return nil
end

local METHODS = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true }

-- One line as an endpoint: { method, path, status (three digits after → or ->, or nil), note }, or nil.
-- Backticks are dropped first; the method must be in capitals, the path start with /, and anything after the
-- path or status follow a separator ("POST /a → 201 — makes one"), or the line is a sentence.
function planblocks.endpoint(line)
  local method, path, rest = line:gsub("`", ""):match("^%s*(%u+)%s+(/%S*)(.*)$")
  if not method or not METHODS[method] then return nil end
  local colon = path:match("[:,;]$")
  if colon then path, rest = path:sub(1, -2), colon .. rest end
  rest = trim(rest)
  local status, after
  for _, arrow in ipairs({ "→", "->" }) do
    if rest:sub(1, #arrow) == arrow then
      status, after = rest:sub(#arrow + 1):match("^%s*(%d%d%d)%f[%D](.*)$")
      if status then rest = after break end
    end
  end
  -- What follows is a note only after a separator; words straight after it make a sentence, not an endpoint.
  if not separated(rest) and not (rest:sub(1, #"→") == "→" or rest:sub(1, 2) == "->") then return nil end
  return { method = method, path = path, status = status, note = clean(rest) }
end

-- A paragraph whose every line, or a list whose every item, is an endpoint:
-- { kind = "endpoints", rows = { endpoint }, source }. Nil for anything else.
function planblocks.endpoints(block)
  local lines = block.kind == "paragraph" and block.lines or block.kind == "list" and block.items
  if not lines or #lines == 0 then return nil end
  local rows = {}
  for _, line in ipairs(lines) do
    local row = planblocks.endpoint(line)
    if not row then return nil end
    rows[#rows + 1] = row
  end
  return { kind = "endpoints", rows = rows, source = block.source }
end

-- The recognisers, in the order they are tried.
planblocks.RECOGNISERS = { planblocks.fileMap, planblocks.endpoints }

-- The blocks with each one a recogniser knows replaced by the block it lifts; the rest as they were.
function planblocks.lift(blocks)
  local out, heading = {}, nil
  for i, block in ipairs(blocks) do
    local lifted
    for _, recognise in ipairs(planblocks.RECOGNISERS) do
      lifted = recognise(block, { heading = heading, before = blocks[i - 1] })
      if lifted then break end
    end
    out[#out + 1] = lifted or block
    if block.kind == "heading" then heading = block end
  end
  return out
end

return planblocks
