--- Generate wiki documentation from config/default.lua annotations.
--- Run with: nvim --headless --noplugin -c "luafile scripts/generate_wiki_docs.lua" -c "qa!"

local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local config_path = project_root .. "/lua/obsidian/config/default.lua"
local docs_dir = project_root .. "/docs"

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
-- Parsing config/default.lua (using treesitter)
--------------------------------------------------------------------------------

--- Walk backwards from a field's start row to find the annotation block above it,
--- including any @alias lines separated by blank lines.
---@param lines string[] 1-indexed file lines
---@param field_start_row integer 0-indexed treesitter row
---@return integer annotation_start_row 0-indexed
local function find_annotations_start(lines, field_start_row)
  -- Step 1: walk backwards through contiguous `---` comment lines.
  local i = field_start_row - 1
  while i >= 0 and lines[i + 1]:match "^%s*%-%-%-" do
    i = i - 1
  end
  local comment_start = i + 1

  -- Step 2: skip blank lines, then collect any @alias lines above.
  local j = comment_start - 1
  while j >= 0 and lines[j + 1]:match "^%s*$" do
    j = j - 1
  end
  local alias_end = j
  while j >= 0 and lines[j + 1]:match "^%s*%-%-%-@alias" do
    j = j - 1
  end
  -- Only extend comment_start if we actually found @alias lines.
  if j < alias_end then
    comment_start = j + 1
  end

  return comment_start
end

--- Parse config/default.lua using treesitter and extract sections.
--- Returns a table mapping config keys to their annotation+code text blocks.
---@param path string
---@return table<string, string>
local function parse_config(path)
  local lines = vim.fn.readfile(path)
  local source = table.concat(lines, "\n")
  local parser = vim.treesitter.get_string_parser(source, "lua")
  local tree = assert(parser:parse(), "no tree")[1]

  -- Navigate: chunk > return_statement > expression_list > table_constructor
  local root = tree:root()
  local ret_node = root:child(1) -- return_statement
  assert(ret_node and ret_node:type() == "return_statement", "Expected a return statement, got " .. ret_node:type())
  local expr_node = ret_node:child(1) -- expression_list
  assert(expr_node and expr_node:type() == "expression_list", "Expected an expression list, got " .. expr_node:type())
  local tbl_node = expr_node:child(0) -- table_constructor
  assert(tbl_node and tbl_node:type() == "table_constructor", "Expected a table constructor, got " .. tbl_node:type())

  ---@type table<string, string>
  local sections = {}

  for field in tbl_node:iter_children() do
    if field:type() == "field" then
      local name_node = field:field("name")[1]
      if name_node then
        local name = vim.treesitter.get_node_text(name_node, source)
        local sr, _, er = field:range()
        local ann_start = find_annotations_start(lines, sr)

        -- Only include fields that have annotations above them.
        if ann_start < sr then
          -- Build the block: annotation lines + field assignment lines.
          local block = {}
          for i = ann_start + 1, er + 1 do
            if lines[i] then
              -- Strip the 2-space indent (lines are inside `return { ... }`).
              block[#block + 1] = lines[i]:gsub("^  ", "")
            end
          end

          -- Remove trailing comma from the last line.
          if #block > 0 then
            block[#block] = block[#block]:gsub(",%s*$", "")
          end

          sections[name] = table.concat(block, "\n")
        end
      end
    end
  end

  return sections
end

--------------------------------------------------------------------------------
-- TOC generation
--------------------------------------------------------------------------------

--- Convert heading text to a GitHub-style anchor.
---@param text string
---@return string
local function heading_to_anchor(text)
  return (text:lower():gsub("[^%w%s%-]", ""):gsub("%s+", "-"))
end

--- Extract all level-2 headings from lines.
---@param lines string[]
---@return { text: string, line_idx: integer }[]
local function extract_headings(lines)
  local headings = {}
  for i, line in ipairs(lines) do
    local text = line:match "^## (.+)$"
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
    if line:match "^## " then
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
    if lines[i] and lines[i]:match "^%- %[" then
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
    if line:match "^## Options%s*$" then
      start_idx = i
    elseif start_idx and line:match "^## " then
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
  for line in (block .. "\n"):gmatch "([^\n]*)\n" do
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
      while resume <= #lines and lines[resume]:match "^%s*$" do
        resume = resume + 1
      end
      for i = resume, #lines do
        new_lines[#new_lines + 1] = lines[i]
      end
      lines = new_lines
    end
  end

  -- Ensure file ends with exactly one newline.
  while #lines > 0 and lines[#lines]:match "^%s*$" do
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

print "Done."
