local Document = require "obsidian.document"
local Section = require "obsidian.section"

local M = {}
local foldexpr = "v:lua.require'obsidian.folding'.foldexpr()"
local foldtext = "v:lua.require'obsidian.folding'.foldtext()"

---@alias obsidian.folding.GlobalState "overview"|"contents"|"show_all"

---@type table<string, obsidian.folding.GlobalState?>
local next_state = { overview = "contents", contents = "show_all", show_all = "overview" }

---@class obsidian.folding.Subtree
---@field first integer
---@field last integer
---@field children obsidian.folding.Subtree[] Foldable direct children.

---@class obsidian.folding.Layout
---@field levels table<integer, integer|string>
---@field subtrees table<integer, obsidian.folding.Subtree> Indexed by heading line, including Setext underlines.
---@field entries integer[] Start lines of entries with foldable bodies, including frontmatter.
---@field properties obsidian.folding.Subtree? The two-state YAML frontmatter fold.

---@type table<obsidian.parse.Document, obsidian.folding.Layout>
local layouts = setmetatable({}, { __mode = "k" })

---@param document obsidian.parse.Document
---@return obsidian.folding.Layout
local function build_layout(document)
  local levels, subtrees, entries = {}, {}, {}
  local starts, ends = {}, {}

  local function add_fold(first, last, depth)
    starts[first] = depth -- An entry fold can start on the same line as its subtree fold.
    ends[last] = math.min(ends[last] or depth, depth)
  end

  local frontmatter = document:replaceable_frontmatter_range()
  local properties
  if frontmatter then
    properties = { first = 1, last = frontmatter.end_row, children = {} }
    add_fold(properties.first, properties.last, 1)
    entries[#entries + 1] = properties.first
  end

  local depths = {}
  local sections = Section.parse(document.lines, { start_row = document:body_start_row(), document = document })
  for _, section in ipairs(sections) do
    local heading = section.heading_range
    local first, last = heading.start_row + 1, section.range.end_row
    if section.header and last > heading.end_row then
      local parent = section.parent
      local depth = parent and depths[parent] + 1 or 1
      depths[section] = depth
      local tree = { first = first, last = last, children = {} }
      for lnum = first, heading.end_row do
        subtrees[lnum] = tree
      end
      if parent then
        local siblings = subtrees[parent.heading_range.start_row + 1].children
        siblings[#siblings + 1] = tree
      end

      add_fold(first, last, depth)
      local body_end = section.content_range.end_row
      if body_end > heading.end_row then
        entries[#entries + 1] = first
        if body_end < last then
          add_fold(first, body_end, depth + 1)
        end
      end
    end
  end

  local depth = 0
  for lnum = 1, #document.lines do
    -- Explicit end markers separate adjacent siblings, even when multiple
    -- nested folds end here and the next heading starts at the same depth.
    if starts[lnum] then
      depth = starts[lnum]
      levels[lnum] = ">" .. depth
    elseif ends[lnum] then
      levels[lnum] = "<" .. ends[lnum]
      depth = ends[lnum] - 1
    elseif depth > 0 then
      levels[lnum] = depth
    end
  end

  return { levels = levels, subtrees = subtrees, entries = entries, properties = properties }
end

---@return obsidian.folding.Layout
local function layout()
  local document = Document.get(0)
  local cached = layouts[document]
  if not cached then
    cached = build_layout(document)
    layouts[document] = cached
  end
  return cached
end

M.foldexpr = function()
  return layout().levels[vim.v.lnum] or 0
end

M.foldtext = function()
  if vim.v.foldstart == 1 and layout().properties then
    return "Properties"
  end
  return vim.fn.foldtext()
end

--- Select Obsidian outline folding in the current window. Leave startup
--- visibility (`foldlevel` and `foldenable`) to the caller.
M.enable = function()
  local wo = vim.wo[0][0]
  if wo.foldexpr ~= foldexpr then
    wo.foldexpr = foldexpr
  end
  if wo.foldmethod ~= "expr" then
    wo.foldmethod = "expr"
  end
  if wo.foldtext ~= foldtext then
    wo.foldtext = foldtext
  end
end

local function configured()
  return vim.wo.foldmethod == "expr" and vim.wo.foldexpr == foldexpr
end

local function restore_cursor(cursor)
  cursor[1] = math.max(1, cursor[1])
  local first = vim.fn.foldclosed(cursor[1])
  if first ~= -1 and first ~= cursor[1] then
    cursor = { first, 0 }
  end
  vim.api.nvim_win_set_cursor(0, cursor)
end

---@param tree obsidian.folding.Subtree
local function subtree_closed(tree)
  return vim.fn.foldclosedend(tree.first) == tree.last
end

---@param tree obsidian.folding.Subtree
local function close_subtree(tree)
  local first = tree.first
  if vim.fn.foldclosed(first) == -1 then
    vim.cmd.foldclose { range = { first } }
  end
  if vim.fn.foldclosed(first) == first and not subtree_closed(tree) then
    -- Close the outer fold when the first close only hid the entry body.
    vim.cmd.foldclose { range = { first } }
  end
end

--- Cycle a heading's subtree or toggle Properties in the current window.
M.cycle = function()
  if not configured() then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local outline = layout()
  local properties = outline.properties
  local tree = properties and cursor[1] <= properties.last and properties or outline.subtrees[cursor[1]]
  if not tree then
    return
  end

  vim.wo[0][0].foldenable = true
  local first = vim.fn.foldclosed(tree.first)
  if first ~= -1 and first ~= tree.first then
    return -- An ancestor hides this heading.
  end
  local folded = subtree_closed(tree)
  local children_only = #tree.children > 0 and first == -1 and vim.iter(tree.children):all(subtree_closed)
  if folded or children_only then
    vim.cmd.foldopen { range = { tree.first, tree.last }, bang = true }
    if folded then
      for _, child in ipairs(tree.children) do
        close_subtree(child)
      end
    end
  else
    close_subtree(tree)
  end
  restore_cursor(cursor)
end

--- Apply a named global view to the current window and buffer.
---@param state obsidian.folding.GlobalState
---@return boolean applied
M.set_global = function(state)
  assert(next_state[state], "Invalid global fold state")
  if not configured() then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local wo = vim.wo[0][0]
  wo.foldenable = true
  wo.foldlevel = state == "overview" and 0 or 99
  vim.cmd.normal { args = { "zX" }, bang = true } -- Reset manual folds without revealing the cursor line.
  if state == "contents" then
    for _, first in ipairs(layout().entries) do
      vim.cmd.foldclose { range = { first } }
    end
  end
  restore_cursor(cursor)

  local states = vim.w.obsidian_fold_states or {}
  states[tostring(vim.api.nvim_get_current_buf())] = state
  vim.w.obsidian_fold_states = states
  return true
end

--- Advance the latest named global view in this window and buffer.
M.cycle_global = function()
  local states = vim.w.obsidian_fold_states or {}
  local last = states[tostring(vim.api.nvim_get_current_buf())]
  M.set_global(next_state[last] or "overview")
end

return M
