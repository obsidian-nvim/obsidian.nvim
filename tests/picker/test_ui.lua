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
_G.picker = Ui.open({ "one", "two" }, {
  prompt = "Preview",
  preview_item = function(value)
    preview_values[#preview_values + 1] = value
    return { buf = preview_buf, pos = { value == "one" and 2 or 3, 0 } }
  end,
})

return {
  values = preview_values,
  shown_buf = vim.api.nvim_win_get_buf(picker.preview_win),
  cursor = vim.api.nvim_win_get_cursor(picker.preview_win),
}
  ]]

  eq({ "one" }, initial.values)
  eq(child.lua_get "preview_buf", initial.shown_buf)
  eq({ 2, 0 }, initial.cursor)

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

local picker = Ui.open({}, {
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
  local result = child.lua [[
local Ui = require "obsidian.picker.ui"
vim.o.columns = 120
vim.o.lines = 40

local preview_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "preview" })
local picker = Ui.open({ "one", "two", "three" }, {
  preview_item = function()
    return { buf = preview_buf }
  end,
})

local function geometry()
  local input = vim.api.nvim_win_get_config(picker.input_win)
  local results = vim.api.nvim_win_get_config(picker.results_win)
  local preview = vim.api.nvim_win_get_config(picker.preview_win)
  local available_lines = vim.o.lines - vim.o.cmdheight
  local outer_width = input.width + 2
  local total_height = results.height + 5
  return {
    input = input,
    results = results,
    preview = preview,
    horizontally_centered = math.abs(input.col * 2 + outer_width - vim.o.columns) <= 1,
    vertically_centered = math.abs(input.row * 2 + total_height - available_lines) <= 1,
    lower_row_aligned = results.row == input.row + 3 and preview.row == input.row + 3,
    right_edge_aligned = preview.col + preview.width + 2 == input.col + outer_width,
  }
end

local before = geometry()
vim.o.columns = 180
vim.o.lines = 60
vim.api.nvim_exec_autocmds("VimResized", {})
local resized = vim.wait(1000, function()
  return vim.api.nvim_win_get_config(picker.input_win).col ~= before.input.col
end, 10, false)
local after = geometry()
picker:cancel()
return { before = before, after = after, resized = resized }
  ]]

  eq(true, result.before.horizontally_centered)
  eq(true, result.before.vertically_centered)
  eq(true, result.before.lower_row_aligned)
  eq(true, result.before.right_edge_aligned)
  eq(true, result.resized)
  eq(true, result.after.horizontally_centered)
  eq(true, result.after.vertically_centered)
  eq(true, result.after.lower_row_aligned)
  eq(true, result.after.right_edge_aligned)
end

T["preserves values and returns the selected value"] = function()
  local result = child.lua [[
local Ui = require "obsidian.picker.ui"
local values = {
  { id = 2, label = "second" },
  { id = 1, label = "first" },
}
local choices
local picker = Ui.open(values, {
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

return T
