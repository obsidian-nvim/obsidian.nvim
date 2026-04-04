--- Generate wiki documentation from config/default.lua annotations.
--- Run with: nvim --headless --noplugin -c "luafile scripts/generate_wiki_docs.lua" -c "qa!"

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local config_path = root .. "/lua/obsidian/config/default.lua"
local docs_dir = root .. "/docs"

--- Hard-coded mapping: config key -> wiki page filename.
--- Only pages in this list are updated.
---@type table<string, string>
local module_pages = {
  statusline = "Statusline.md",
  link = "Link.md",
  note = "Note.md",
  frontmatter = "Frontmatter.md",
  templates = "Template.md",
  search = "Search.md",
  daily_notes = "Daily Notes.md",
  unique_note = "Unique-Note.md",
  attachments = "Attachment.md",
  footer = "Footer.md",
  open = "Open.md",
  checkbox = "Checkbox.md",
}

--------------------------------------------------------------------------------
-- Parsing config/default.lua
--------------------------------------------------------------------------------

--- Count net brace/paren depth change in a line.
---@param line string
---@return integer brace_delta
---@return integer paren_delta
local function depth_deltas(line)
  -- Strip string literals and comments to avoid counting braces inside them.
  local stripped = line
    :gsub("%-%-.*$", "") -- line comments
    :gsub('%b""', "") -- double-quoted strings
    :gsub("%b''", "") -- single-quoted strings

  local bd, pd = 0, 0
  for c in stripped:gmatch(".") do
    if c == "{" then
      bd = bd + 1
    elseif c == "}" then
      bd = bd - 1
    elseif c == "(" then
      pd = pd + 1
    elseif c == ")" then
      pd = pd - 1
    end
  end
  return bd, pd
end

--- Detect if a line is an annotation line (starts with optional whitespace then `---`).
---@param line string
---@return boolean
local function is_annotation(line)
  return line:match("^%s*%-%-%-") ~= nil
end

--- Detect a table/value assignment line like `  key = {` or `  key = (function()`.
--- Returns the key name or nil.
---@param line string
---@return string|nil key
local function assignment_key(line)
  -- Match `  key = {`, `  key = (function()`, `  key = value,`, `  key = require(...)...`
  -- Must be indented exactly 2 spaces (top-level field in the returned table).
  return line:match("^  ([%w_]+)%s*=")
end

--- Parse config/default.lua and extract sections.
--- Returns a table mapping config keys to their annotation+code text blocks.
---@param path string
---@return table<string, string>
local function parse_config(path)
  local f = io.open(path, "r")
  if not f then
    error("Cannot open " .. path)
  end
  local all_lines = {}
  for line in f:lines() do
    all_lines[#all_lines + 1] = line
  end
  f:close()

  ---@type table<string, string>
  local sections = {}
  ---@type string[]
  local annotation_buf = {} -- buffered annotation lines before current section
  ---@type string[]
  local alias_buf = {} -- @alias lines floating between sections
  ---@type string|nil
  local current_key = nil
  ---@type string[]
  local current_lines = {}
  local brace_depth = 0
  local paren_depth = 0
  local in_body = false -- tracking a table assignment body

  local function flush_section()
    if current_key then
      -- Trim trailing empty lines
      while #current_lines > 0 and current_lines[#current_lines]:match("^%s*$") do
        table.remove(current_lines)
      end
      -- Remove trailing comma from last line (top-level table entry ends with `},`)
      if #current_lines > 0 then
        current_lines[#current_lines] = current_lines[#current_lines]:gsub(",%s*$", "")
      end
      -- Strip common 2-space leading indent (lines are inside `return { ... }` in default.lua).
      for i, l in ipairs(current_lines) do
        current_lines[i] = l:gsub("^  ", "")
      end
      sections[current_key] = table.concat(current_lines, "\n")
    end
    current_key = nil
    current_lines = {}
    brace_depth = 0
    paren_depth = 0
    in_body = false
  end

  for _, line in ipairs(all_lines) do
    if in_body then
      -- We're inside a table assignment body.
      current_lines[#current_lines + 1] = line
      local bd, pd = depth_deltas(line)
      brace_depth = brace_depth + bd
      paren_depth = paren_depth + pd

      -- Check for nested @class inside the body (e.g., CustomTemplateOpts inside templates).
      -- These are kept as part of the parent section.

      if brace_depth <= 0 and paren_depth <= 0 then
        flush_section()
      end
    elseif is_annotation(line) then
      -- Check if it's an @alias line (floating between sections).
      if line:match("^%s*%-%-%-@alias") then
        alias_buf[#alias_buf + 1] = line
      else
        annotation_buf[#annotation_buf + 1] = line
      end
    else
      -- Non-annotation, non-body line.
      local key = assignment_key(line)
      if key and #annotation_buf > 0 then
        -- Start of a new section with annotations.
        flush_section()
        current_key = key

        -- Prepend any buffered aliases.
        for _, a in ipairs(alias_buf) do
          current_lines[#current_lines + 1] = a
        end
        if #alias_buf > 0 then
          current_lines[#current_lines + 1] = ""
        end
        alias_buf = {}

        -- Add the annotation block.
        for _, a in ipairs(annotation_buf) do
          current_lines[#current_lines + 1] = a
        end
        annotation_buf = {}

        -- Add the assignment line.
        current_lines[#current_lines + 1] = line

        local bd, pd = depth_deltas(line)
        brace_depth = brace_depth + bd
        paren_depth = paren_depth + pd

        if brace_depth > 0 or paren_depth > 0 then
          in_body = true
        else
          -- Single-line assignment (e.g., `key = value,`).
          flush_section()
        end
      else
        -- Not a section start or no annotations: discard buffered annotations.
        annotation_buf = {}
        -- Keep alias_buf as it may apply to the next section.
      end
    end
  end

  -- Flush any remaining section.
  flush_section()

  return sections
end

--------------------------------------------------------------------------------
-- TOC generation
--------------------------------------------------------------------------------

--- Convert heading text to a GitHub-style anchor.
---@param text string
---@return string
local function heading_to_anchor(text)
  return text:lower():gsub("[^%w%s%-]", ""):gsub("%s+", "-")
end

--- Extract all level-2 headings from lines.
---@param lines string[]
---@return { text: string, line_idx: integer }[]
local function extract_headings(lines)
  local headings = {}
  for i, line in ipairs(lines) do
    local text = line:match("^## (.+)$")
    if text then
      headings[#headings + 1] = { text = text, line_idx = i }
    end
  end
  return headings
end

--- Generate a TOC as a list of markdown links.
---@param headings { text: string }[]
---@return string[]
local function generate_toc(headings)
  local toc = {}
  for _, h in ipairs(headings) do
    toc[#toc + 1] = string.format("- [%s](#%s)", h.text, heading_to_anchor(h.text))
  end
  return toc
end

--------------------------------------------------------------------------------
-- Wiki page updating
--------------------------------------------------------------------------------

--- Find the index of the first level-2 heading in lines.
---@param lines string[]
---@return integer|nil
local function first_heading_idx(lines)
  for i, line in ipairs(lines) do
    if line:match("^## ") then
      return i
    end
  end
  return nil
end

--- Check if lines before the first heading look like a TOC (lines starting with `- [`).
---@param lines string[]
---@param first_h_idx integer
---@return integer|nil start_idx, integer|nil end_idx
local function find_existing_toc(lines, first_h_idx)
  local start_idx, end_idx
  for i = 1, first_h_idx - 1 do
    if lines[i]:match("^%- %[") then
      if not start_idx then
        start_idx = i
      end
      end_idx = i
    end
  end
  return start_idx, end_idx
end

--- Find the range of the `## Options` section.
--- Returns start line index (the `## Options` line) and end line index (exclusive, next ## or #lines+1).
---@param lines string[]
---@return integer|nil start_idx, integer end_idx
local function find_options_range(lines)
  local start_idx
  for i, line in ipairs(lines) do
    if line:match("^## Options%s*$") then
      start_idx = i
    elseif start_idx and line:match("^## ") then
      return start_idx, i
    end
  end
  if start_idx then
    return start_idx, #lines + 1
  end
  return nil, #lines + 1
end

--- Build the `## Options` section content.
---@param block string The annotation+defaults block from the parser.
---@return string[]
local function build_options_section(block)
  local result = {}
  result[#result + 1] = "## Options"
  result[#result + 1] = ""
  result[#result + 1] = "```lua"
  for line in (block .. "\n"):gmatch("([^\n]*)\n") do
    result[#result + 1] = line
  end
  result[#result + 1] = "```"
  return result
end

--- Update a single wiki page.
---@param page_path string
---@param options_block string|nil
local function update_page(page_path, options_block)
  local f = io.open(page_path, "r")
  if not f then
    io.stderr:write("Warning: cannot open " .. page_path .. ", skipping\n")
    return
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()

  -- Step 1: Replace or append the ## Options section.
  if options_block then
    local opt_start, opt_end = find_options_range(lines)
    local new_options = build_options_section(options_block)

    if opt_start then
      -- Replace existing ## Options section.
      local new_lines = {}
      for i = 1, opt_start - 1 do
        new_lines[#new_lines + 1] = lines[i]
      end
      for _, l in ipairs(new_options) do
        new_lines[#new_lines + 1] = l
      end
      for i = opt_end, #lines do
        new_lines[#new_lines + 1] = lines[i]
      end
      lines = new_lines
    else
      -- Append ## Options at the end.
      lines[#lines + 1] = ""
      for _, l in ipairs(new_options) do
        lines[#lines + 1] = l
      end
    end
  end

  -- Step 2: Generate/update TOC.
  local headings = extract_headings(lines)
  local fh_idx = first_heading_idx(lines)

  if fh_idx then
    local toc_start, toc_end = find_existing_toc(lines, fh_idx)

    if #headings > 2 then
      -- Generate TOC.
      local toc_lines = generate_toc(headings)

      if toc_start then
        -- Replace existing TOC.
        local new_lines = {}
        for i = 1, toc_start - 1 do
          new_lines[#new_lines + 1] = lines[i]
        end
        for _, l in ipairs(toc_lines) do
          new_lines[#new_lines + 1] = l
        end
        for i = toc_end + 1, #lines do
          new_lines[#new_lines + 1] = lines[i]
        end
        lines = new_lines
      else
        -- Insert TOC at the top.
        local new_lines = {}
        for _, l in ipairs(toc_lines) do
          new_lines[#new_lines + 1] = l
        end
        new_lines[#new_lines + 1] = ""
        for _, l in ipairs(lines) do
          new_lines[#new_lines + 1] = l
        end
        lines = new_lines
      end
    elseif toc_start then
      -- <= 2 headings but existing TOC found: remove it.
      local new_lines = {}
      for i = 1, toc_start - 1 do
        new_lines[#new_lines + 1] = lines[i]
      end
      -- Skip blank lines immediately after the old TOC.
      local resume = toc_end + 1
      while resume <= #lines and lines[resume]:match("^%s*$") do
        resume = resume + 1
      end
      for i = resume, #lines do
        new_lines[#new_lines + 1] = lines[i]
      end
      lines = new_lines
    end
  end

  -- Ensure file ends with exactly one newline.
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end

  -- Write the file.
  local out = io.open(page_path, "w")
  if not out then
    error("Cannot write " .. page_path)
  end
  out:write(table.concat(lines, "\n") .. "\n")
  out:close()

  print("Updated: " .. page_path)
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local sections = parse_config(config_path)

for key, page_name in pairs(module_pages) do
  local page_path = docs_dir .. "/" .. page_name
  local block = sections[key]
  if not block then
    io.stderr:write(string.format("Warning: no config section found for key '%s', skipping %s\n", key, page_name))
  end
  update_page(page_path, block)
end

print("Done.")
