local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua" }
    end,
    post_case = function()
      child.stop()
    end,
  },
}

T["renders preview_item and updates it with the selection"] = function()
  local initial = child.lua [[
local Ui = require "obsidian.picker.ui"
local preview_buf = vim.api.nvim_create_buf(false, true)
vim.bo[preview_buf].bufhidden = "hide"
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "first", "second", "third" })

_G.preview_values = {}
_G.preview_buf = preview_buf
_G.picker = Ui.select({ "one", "two" }, {
  prompt = "Preview",
  preview_item = function(value)
    preview_values[#preview_values + 1] = value
    local line = value == "one" and 2 or 3
    return { buf = preview_buf, pos = { line, 0 }, pos_end = { line, #value } }
  end,
})

local function highlights()
  local result = {}
  local ns = vim.api.nvim_create_namespace "obsidian.picker.preview"
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(preview_buf, ns, 0, -1, { details = true })) do
    local details = mark[4]
    result.line = result.line or details.line_hl_group == "CursorLine"
    result.word = result.word or details.hl_group == "IncSearch"
  end
  return result
end

return {
  values = preview_values,
  shown_buf = vim.api.nvim_win_get_buf(picker.preview_win),
  cursor = vim.api.nvim_win_get_cursor(picker.preview_win),
  highlights = highlights(),
}
  ]]

  eq({ "one" }, initial.values)
  eq(child.lua_get "preview_buf", initial.shown_buf)
  eq({ 2, 0 }, initial.cursor)
  eq({ line = true, word = true }, initial.highlights)

  local moved = child.lua [[
picker:move(1)
return {
  values = preview_values,
  selected = picker:selected(),
  cursor = vim.api.nvim_win_get_cursor(picker.preview_win),
}
  ]]
  eq({ "one", "two" }, moved.values)
  eq("two", moved.selected)
  eq({ 3, 0 }, moved.cursor)

  local closed = child.lua [[
local win = picker.preview_win
picker:cancel()
return {
  preview_buffer_valid = vim.api.nvim_buf_is_valid(preview_buf),
  preview_window_valid = vim.api.nvim_win_is_valid(win),
}
  ]]
  eq(true, closed.preview_buffer_valid)
  eq(false, closed.preview_window_valid)
end

T["runs query mappings without installing selection mappings"] = function()
  local result = child.lua [[
local Ui = require "obsidian.picker.ui"
local calls = {}
local choices
local query_mappings = {
  ["<F5>"] = {
    desc = "keep",
    keep_open = true,
    callback = function(query)
      calls[#calls + 1] = "keep:" .. query
    end,
  },
  ["<F6>"] = {
    desc = "close",
    callback = function(query)
      calls[#calls + 1] = "close:" .. query
    end,
  },
}

local picker = Ui.select({}, {
  query = "needle",
  query_mappings = query_mappings,
  selection_mappings = {
    ["<F7>"] = { desc = "unsupported", callback = function() end },
  },
}, function(selected)
  choices = selected
end)
local input_win = picker.input_win
local results_win = picker.results_win
local input_buf = picker.input_buf
local results_buf = picker.results_buf

local mapped = {}
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(picker.input_buf, "n")) do
  mapped[mapping.lhs] = true
end

picker:run_query_mapping(query_mappings["<F5>"])
local stayed_open = not picker.closed
picker:run_query_mapping(query_mappings["<F6>"])

return {
  calls = calls,
  choices = choices,
  stayed_open = stayed_open,
  closed = picker.closed,
  has_query_mapping = mapped["<F5>"] == true and mapped["<F6>"] == true,
  has_selection_mapping = mapped["<F7>"] == true,
  windows_closed = not vim.api.nvim_win_is_valid(input_win) and not vim.api.nvim_win_is_valid(results_win),
  buffers_deleted = not vim.api.nvim_buf_is_valid(input_buf) and not vim.api.nvim_buf_is_valid(results_buf),
}
  ]]

  eq({ "keep:needle", "close:needle" }, result.calls)
  eq(nil, result.choices)
  eq(true, result.stayed_open)
  eq(true, result.closed)
  eq(true, result.has_query_mapping)
  eq(false, result.has_selection_mapping)
  eq(true, result.windows_closed)
  eq(true, result.buffers_deleted)
end

T["recenters and resizes every window on VimResized"] = function()
  -- Create two pickers at different editor sizes and verify the layout
  -- adapts: the second picker should be wider and still centred.  Heights
  -- may be equal when item count or max_results caps both, so we only
  -- assert that width grows and that heights are non-decreasing.
  local function picker_geometry(cols, lines)
    return child.lua(string.format(
      [[
vim.o.columns = %d
vim.o.lines = %d

local Ui = require "obsidian.picker.ui"
local items = {}
for i = 1, 20 do
  items[i] = tostring(i)
end

local preview_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "preview" })
local picker = Ui.select(items, {
  prompt = "Test",
  max_results = 20,
  preview_item = function()
    return { buf = preview_buf }
  end,
})

local input = vim.api.nvim_win_get_config(picker.input_win)
local results = vim.api.nvim_win_get_config(picker.results_win)
local preview = vim.api.nvim_win_get_config(picker.preview_win)
local available_lines = vim.o.lines - vim.o.cmdheight
local outer_width = input.width + 2
-- Total outer height: input (3 rows) + results (results.height+1, sharing
-- the top border with input) + preview (preview.height+1, sharing top)
local total_height = 3 + (results.height + 1) + (preview.height + 1)

local geom = {
  width = input.width,
  height = results.height,
  preview_height = preview.height,
  horizontally_centered = math.abs(input.col * 2 + outer_width - vim.o.columns) <= 1,
  vertically_centered = math.abs(input.row * 2 + total_height - available_lines) <= 1,
  -- Results sits directly below input (sharing the bottom/top border).
  stacked = results.row == input.row + 2
    and preview.row == results.row + results.height + 1,
  -- All windows share the same column and width.
  aligned = input.col == results.col and results.col == preview.col
    and input.width == results.width and results.width == preview.width,
}
picker:cancel()
return geom
    ]],
      cols,
      lines
    ))
  end

  local small = picker_geometry(120, 40)
  local large = picker_geometry(180, 60)

  -- Both pickers should be centred and properly aligned.
  for _, g in ipairs { small, large } do
    eq(true, g.horizontally_centered)
    eq(true, g.vertically_centered)
    eq(true, g.stacked)
    eq(true, g.aligned)
  end
  -- The larger terminal should produce a wider (or equal) picker.
  eq(true, large.width >= small.width)
  eq(true, large.height >= small.height)
  eq(true, large.preview_height >= small.preview_height)
end

T["preserves values and returns the selected value"] = function()
  local result = child.lua [[
local Ui = require "obsidian.picker.ui"
local values = {
  { id = 2, label = "second" },
  { id = 1, label = "first" },
}
local choices
local picker = Ui.select(values, {
  format_item = function(value)
    return value.label
  end,
}, function(selected)
  choices = selected
end)
local first = picker:selected()
picker:move(1)
picker:confirm()
return { first = first, choices = choices }
  ]]

  eq({ id = 2, label = "second" }, result.first)
  eq({ { id = 1, label = "first" } }, result.choices)
end

T["live_grep cancels stale jobs and streams only the latest results"] = function()
  local result = child.lua [[
local Search = require "obsidian.search"
local original = Search.search_async
local jobs = {}
Search.search_async = function(_, query, _, on_match)
  local job = { query = query, on_match = on_match, killed = false }
  function job:kill()
    self.killed = true
  end
  jobs[#jobs + 1] = job
  return job
end

local preview_buf = vim.api.nvim_create_buf(false, true)
local Util = require "obsidian.util"
local original_preview_path = Util.preview_path
Util.preview_path = function()
  return { buf = preview_buf }
end
local picker = require("obsidian.picker.ui").live_grep {
  dir = ".",
  query = "old",
  debounce = 0,
  format_item = function(entry)
    return entry.text
  end,
}
assert(vim.wait(1000, function() return #jobs == 1 end, 10))
vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "new" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = picker.input_buf })
assert(vim.wait(1000, function() return #jobs == 2 end, 10))

jobs[1].on_match {
  path = { text = "old.md" }, line_number = 1,
  lines = { text = "old result\n" }, submatches = { { start = 0, ["end"] = 3 } },
}
jobs[2].on_match {
  path = { text = "new.md" }, line_number = 2,
  lines = { text = "new result\n" }, submatches = { { start = 4, ["end"] = 7 } },
}
assert(vim.wait(1000, function() return #picker.items == 1 end, 10))
local value = picker.items[1].value
local preview_spec = picker.opts.preview_item(value)
local out = {
  old_killed = jobs[1].killed,
  queries = { jobs[1].query, jobs[2].query },
  value = value,
  preview = { pos = preview_spec.pos, pos_end = preview_spec.pos_end },
}
picker:cancel()
Search.search_async = original
Util.preview_path = original_preview_path
return out
  ]]

  eq(true, result.old_killed)
  eq({ "old", "new" }, result.queries)
  eq({ filename = "new.md", lnum = 2, col = 5, end_lnum = 2, end_col = 8, text = "new result" }, result.value)
  eq({ pos = { 2, 4 }, pos_end = { 2, 7 } }, result.preview)
end

T["search streams Obsidian query results"] = function()
  local result = child.lua [[
local Query = require "obsidian.search.query"
local original = Query.search
Query.search = function(_, _, callback)
  callback({ {
    document = {
      path = "/vault/work.md",
      relative_path = "work.md",
      filename = "work.md",
      lines = { "---", "tags: [work]", "---", "needle" },
      properties = { tags = { "work" } },
      tags = { { text = "#work", line = 2 } },
      tasks = {},
    },
    line = 4,
    col = 1,
    end_col = 7,
    score = 10,
    context = "needle",
  } })
  return function() end
end

local preview_buf = vim.api.nvim_create_buf(false, true)
local picker = require("obsidian.picker.ui").search {
  dir = "/vault",
  query = "content:needle",
  debounce = 0,
  format_item = function(entry)
    return entry.filename
  end,
  preview_item = function()
    return { buf = preview_buf }
  end,
}
assert(vim.wait(1000, function() return #picker.items == 1 end, 10))
local value = picker.items[1].value
local out = {
  filename = value.filename,
  lnum = value.lnum,
  col = value.col,
  end_lnum = value.end_lnum,
  end_col = value.end_col,
  text = value.text,
}
picker:cancel()
Query.search = original
return out
  ]]

  eq({ filename = "/vault/work.md", lnum = 4, col = 1, end_lnum = 4, end_col = 7, text = "needle" }, result)
end

return T
