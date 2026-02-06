local M = {}
local util = require "obsidian.util"

-- TODO: append referenced footnotes

---@class obsidian.Slide
---@field title string: The title of the slide
---@field body string[]: The body of slide

local new_slide = function()
  return { title = "", body = {} }
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
  return slides
end

return M
