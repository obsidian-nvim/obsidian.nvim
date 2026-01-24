local M = {}
local util = require "obsidian.util"

-- Remove only lines before the first line with content (whitespace-only counts as empty).
local clean_slide = function(slide)
  local first = nil
  for i, line in ipairs(slide.body) do
    if line:match "%S" then -- has some non-whitespace
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

local new_slide = function()
  return { title = "", body = {} }
end

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of slide

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slide[]
M.parse = function(lines)
  local slides = {}

  local current_slide = new_slide()

  for _, line in ipairs(lines) do
    if line == "---" then
      slides[#slides + 1] = clean_slide(current_slide)
      current_slide = new_slide()
    else
      line = line:gsub("%s*$", "")

      if current_slide.title == "" and util.is_header(line) then
        current_slide.title = line
      else
        current_slide.body[#current_slide.body + 1] = line
      end
    end
  end
  slides[#slides + 1] = clean_slide(current_slide)

  return slides
end

return M
