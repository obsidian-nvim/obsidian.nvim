local M = {}
local footnotes = require "obsidian.footnotes"
local util = require "obsidian.util"

---@class obsidian.Slide
---@field title string: The title of the slide
---@field body string[]: The body of slide

local new_slide = function()
  return { title = "", body = {} }
end

---@param line string
---@return boolean
local function is_blank(line)
  return line:match "^%s*$" ~= nil
end

---@param line string
---@return boolean
local function is_footnotes_header(line)
  return line:match "^#+%s+[Ff]ootnotes%s*$" ~= nil
end

---@param lines string[]
---@param i integer
---@return boolean
local function is_blank_at(lines, i)
  local line = lines[i]
  return line ~= nil and is_blank(line)
end

---@param lines string[]
---@param i integer
---@return boolean
local function is_footnotes_header_at(lines, i)
  local line = lines[i]
  return line ~= nil and is_footnotes_header(line)
end

---@param lines string[]
---@return string[] body_lines
---@return table<string, string> definitions
local function strip_trailing_footnotes(lines)
  local i = #lines
  while i > 0 and is_blank_at(lines, i) do
    i = i - 1
  end

  local defs = {}
  local found = false
  while i > 0 do
    local line = lines[i]
    if line == nil then
      break
    end

    local id, text = footnotes.parse_definition(line)
    if id then
      defs[id] = text
      found = true
      i = i - 1
    elseif is_blank(line) then
      i = i - 1
    else
      break
    end
  end

  if not found then
    return lines, defs
  end

  while i > 0 and is_blank_at(lines, i) do
    i = i - 1
  end

  if i > 0 and is_footnotes_header_at(lines, i) then
    i = i - 1
    while i > 0 and is_blank_at(lines, i) do
      i = i - 1
    end
  end

  if i > 0 and lines[i] == "---" then
    i = i - 1
  end

  local body_lines = {}
  for j = 1, i do
    body_lines[#body_lines + 1] = lines[j]
  end

  return body_lines, defs
end

---@param line string
---@param refs string[]
---@param seen table<string, boolean>
local function collect_footnote_refs(line, refs, seen)
  local init = 1
  while true do
    local m_start, m_end, id = line:find("%[%^([^%]%[%s]+)%]", init)
    if not m_start then
      break
    end
    if (m_start == 1 or line:sub(m_start - 1, m_start - 1) ~= "[") and not seen[id] then
      seen[id] = true
      refs[#refs + 1] = id
    end
    ---@cast m_end -nil
    init = m_end + 1
  end
end

---@param slides obsidian.Slide[]
---@param defs table<string, string>
local function append_referenced_footnotes(slides, defs)
  for _, slide in ipairs(slides) do
    local refs = {}
    local seen = {}
    collect_footnote_refs(slide.title, refs, seen)
    for _, line in ipairs(slide.body) do
      collect_footnote_refs(line, refs, seen)
    end

    local first = true
    for _, id in ipairs(refs) do
      local text = defs[id]
      if text then
        if first then
          if #slide.body > 0 and not is_blank(slide.body[#slide.body]) then
            slide.body[#slide.body + 1] = ""
          end
          first = false
        end
        slide.body[#slide.body + 1] = ("[^%s]: %s"):format(id, text)
      end
    end
  end
end

-- Remove only lines before the first line with content (whitespace-only counts as empty).
local clean_slide = function(slide)
  local first = nil
  for i, line in ipairs(slide.body) do
    if line:match "%S" then
      first = i
      break
    end
  end

  if not first then
    slide.body = {}
    return slide
  end

  if first > 1 then
    local new_body = {}
    for i = first, #slide.body do
      new_body[#new_body + 1] = slide.body[i]
    end
    slide.body = new_body
  end

  return slide
end

-- TODO: use treesitter
-- Strip Obsidian markdown comments (%%...%%) and HTML comments (<!--...-->).
-- If the result is empty/whitespace-only, returns nil to indicate "drop line".
local strip_comments = function(line)
  if not line then
    return nil
  end

  -- remove %%...%% (non-greedy, same-line)
  line = line:gsub("%%%%.-%%%%", "")

  -- remove <!--...--> (non-greedy, same-line)
  line = line:gsub("<!%-%-.-%-%->", "")

  -- collapse edges (optional; helps decide drop-line accurately)
  line = line:gsub("%s*$", "")

  return line
end

--- Takes a markdown document and parse them into a list of slides
---@param lines string[]: The lines in the buffer
---@return obsidian.Slide[]
M.parse = function(lines)
  local defs
  lines, defs = strip_trailing_footnotes(lines)

  local slides = {}
  local current_slide = new_slide()

  for _, raw in ipairs(lines) do
    if raw == "---" then
      slides[#slides + 1] = clean_slide(current_slide)
      current_slide = new_slide()
    else
      local line = strip_comments(raw)

      -- drop line if it was only comments/whitespace
      if line then
        if current_slide.title == "" and util.is_header(line) then
          current_slide.title = line
        else
          current_slide.body[#current_slide.body + 1] = line
        end
      end
    end
  end

  slides[#slides + 1] = clean_slide(current_slide)
  append_referenced_footnotes(slides, defs)
  return slides
end

return M
