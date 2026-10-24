local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[
vim.cmd.runtime "plugin/obsidian.lua"
_G.commands = require("obsidian").commands
_G.errors = {}
require("obsidian.log").err = function(message)
  errors[#errors + 1] = message
end
_G.complete = function(cmdline)
  return commands.get_completions(cmdline:match("(%S*)$") or "", cmdline, #cmdline)
end
_G.has_command = function(name, cmdline)
  return vim.list_contains(complete(cmdline or "Obsidian "), name)
end
]],
}

T["add accepts a function without a module and defaults to zero arguments"] = function()
  local result = child.lua [[
local calls = 0
commands.add { name = "custom", fn = function(data)
  calls = calls + 1
  assert(data.args == "" and #data.fargs == 0)
end }
vim.cmd.Obsidian "custom"
vim.cmd "Obsidian custom extra"
return { calls, has_command("custom"), #errors, commands.commands.custom.nargs }
]]
  eq({ 1, true, 1, 0 }, result)
end

T["add replaces a command and del is idempotent"] = function()
  local result = child.lua [[
local calls = {}
commands.add { name = "custom", fn = function() calls[#calls + 1] = "old" end }
commands.add { name = "custom", fn = function() calls[#calls + 1] = "new" end }
vim.cmd.Obsidian "custom"
commands.del "custom"
commands.del "custom"
vim.cmd.Obsidian "custom"
return { calls, has_command("custom"), #errors }
]]
  eq({ { "new" }, false, 1 }, result)
end

T["invalid specs fail at registration"] = function()
  local result = child.lua [[
local invalid = {
  false,
  {},
  { name = "" },
  { name = "has spaces", fn = function() end },
  { name = "custom", fn = "not a function" },
  { name = "custom", fn = function() end, cond = true },
  { name = "custom", fn = function() end, range = "yes" },
  { name = "custom", fn = function() end, complete = {} },
  { name = "custom", fn = function() end, nargs = "invalid" },
  { name = "custom", fn = function() end, nargs = -1 },
  { name = "custom", fn = function() end, nargs = 0.5 },
  { name = "custom", fn = function() end, note_action = true },
  { name = "custom", fn = function() end, func = function() end },
}
local results = {}
for _, spec in ipairs(invalid) do
  results[#results + 1] = pcall(commands.add, spec)
end
return results
]]
  eq(vim.fn["repeat"]({ false }, 13), result)
end

T["argument counts and callback data"] = function()
  local result = child.lua [[
local cases = {
  { nargs = "?", args = "", valid = true },
  { nargs = "?", args = "one", valid = true },
  { nargs = "?", args = "one two", valid = false },
  { nargs = "+", args = "", valid = false },
  { nargs = "+", args = "one two", valid = true },
  { nargs = "*", args = "", valid = true },
  { nargs = "*", args = "one two", valid = true },
  { nargs = 1, args = "", valid = false },
  { nargs = 1, args = "one", valid = true },
  { nargs = 2, args = "one two", valid = true },
  { nargs = "0", args = "", valid = true },
  { nargs = "1", args = "one", valid = true },
}
for _, case in ipairs(cases) do
  local captured
  commands.add { name = "custom", nargs = case.nargs, fn = function(data) captured = data end }
  vim.cmd("Obsidian custom " .. case.args)
  assert((captured ~= nil) == case.valid, vim.inspect(case))
  if captured then
    assert(captured.args == case.args)
    assert(vim.deep_equal(captured.fargs, vim.split(case.args, " ", { trimempty = true })))
  end
end
return true
]]
  eq(true, result)
end

T["conditions dynamically guard discovery and execution"] = function()
  local result = child.lua [[
local enabled, calls = false, 0
local contexts = {}
commands.add {
  name = "custom",
  cond = function(ctx)
    contexts[#contexts + 1] = ctx
    return enabled
  end,
  fn = function() calls = calls + 1 end,
}
local hidden = not has_command("custom")
vim.cmd.Obsidian "custom"
enabled = true
local shown = has_command("custom")
vim.cmd.Obsidian "custom"
enabled = false
vim.cmd.Obsidian "custom"
local ctx = contexts[1]
return { hidden, shown, calls, #errors, ctx.bufnr == vim.api.nvim_get_current_buf(), ctx.in_note, ctx.has_range }
]]
  eq({ true, true, 1, 2, true, false, false }, result)
end

T["note context uses the buffer marker rather than filetype"] = function()
  local result = child.lua [[
commands.add { name = "custom", cond = function(ctx) return ctx.in_note end, fn = function() end }
vim.bo.filetype = "markdown"
local markdown = has_command("custom")
vim.bo.filetype = "quarto"
vim.b.obsidian_buffer = true
local quarto = has_command("custom")
vim.b.obsidian_buffer = nil
return { markdown, quarto, has_command("custom") }
]]
  eq({ false, true, false }, result)
end

T["range support is separate from conditional visibility"] = function()
  local result = child.lua [[
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
local captured = {}
commands.add { name = "both", range = true, fn = function(data) captured[#captured + 1] = data end }
commands.add {
  name = "selection", range = true,
  cond = function(ctx) return ctx.has_range end,
  fn = function() end,
}
commands.add { name = "normal", fn = function() error("range should be rejected") end }
local choices = {
  has_command("both"), has_command("both", "'<,'>Obsidian "),
  has_command("selection"), has_command("selection", "1,2Obsidian "),
  has_command("normal", "%Obsidian "), has_command("both", ".Obsidian "),
}
vim.cmd.Obsidian "both"
vim.cmd "1,2Obsidian both"
vim.cmd "1,2Obsidian normal"
return { choices, captured[1].range, captured[2].range, captured[2].line1, captured[2].line2, #errors }
]]
  eq({ { true, true, false, true, false, true }, 0, 2, 1, 2, 1 }, result)
end

T["completion filters prefixes and preserves function arguments"] = function()
  local result = child.lua [[
local captured
commands.add {
  name = "custom", nargs = "*", range = true,
  complete = function(...) captured = { ... }; return { "value" } end,
  fn = function() end,
}
local names = complete("Obsidian cust")
local line = "1,2Obsidian custom val"
local values = commands.get_completions("val", line, #line)
return { names, values, captured }
]]
  eq({ { "custom" }, { "value" }, { "val", "1,2Obsidian custom val", 22 } }, result)
end

T["argument completion respects availability and string completion types"] = function()
  local result = child.lua [[
local enabled, calls = false, 0
commands.add {
  name = "custom", nargs = "*",
  cond = function() return enabled end,
  complete = function() calls = calls + 1; return { "value" } end,
  fn = function() end,
}
local hidden = complete("Obsidian custom ")
enabled = true
local shown = complete("Obsidian custom ")
local range_hidden = complete("1,2Obsidian custom ")
commands.add { name = "custom", nargs = "*", complete = "command", fn = function() end }
local strings = complete("Obsidian custom Obsid")
return { hidden, shown, range_hidden, calls, vim.list_contains(strings, "Obsidian") }
]]
  eq({ {}, { "value" }, {}, 1, true }, result)
end

T["condition failures do not break other commands or run handlers"] = function()
  local result = child.lua [[
local warnings = {}
vim.notify_once = function(message) warnings[message] = true end
commands.add { name = "broken", cond = function() error("broken condition") end, fn = function() error("ran") end }
commands.add { name = "invalid", cond = function() return "yes" end, fn = function() error("ran") end }
commands.add { name = "working", fn = function() end }
local choices = complete("Obsidian ")
complete("Obsidian ")
vim.cmd.Obsidian "broken"
vim.cmd.Obsidian "invalid"
local messages = table.concat(vim.tbl_keys(warnings), "\n")
return {
  vim.list_contains(choices, "working"), vim.list_contains(choices, "broken"),
  vim.list_contains(choices, "invalid"), #vim.tbl_keys(warnings), #errors,
  messages:find("broken condition", 1, true) ~= nil,
  messages:find("expected a boolean result", 1, true) ~= nil,
}
]]
  eq({ true, false, false, 2, 2, true, true }, result)
end

T["builtin feature conditions follow current config"] = function()
  local result = child.lua [[
vim.b.obsidian_buffer = true
local features = {
  templates = { "template", "new_from_template" },
  checkbox = { "toggle_checkbox" },
  daily_notes = { "dailies", "today", "tomorrow", "yesterday" },
  unique_note = { "unique_note" },
  sync = { "sync" },
}
for feature, names in pairs(features) do
  Obsidian.opts[feature].enabled = false
  for _, name in ipairs(names) do
    assert(not has_command(name), name)
    vim.cmd.Obsidian(name)
  end
  Obsidian.opts[feature].enabled = true
  for _, name in ipairs(names) do
    assert(has_command(name), name)
  end
end
return #errors
]]
  eq(9, result)
end

T["builtin note and range conditions"] = function()
  local result = child.lua [[
local outside = { has_command("new"), has_command("backlinks"), has_command("template") }
vim.b.obsidian_buffer = true
Obsidian.opts.checkbox.enabled = true
return {
  outside, has_command("backlinks"), has_command("toggle_checkbox"),
  has_command("toggle_checkbox", "'<,'>Obsidian "), has_command("extract_note"),
  has_command("extract_note", "'<,'>Obsidian "),
}
]]
  eq({ { true, false, false }, true, true, true, false, true }, result)
end

T["menu preserves originating buffer and range"] = function()
  child.lua [[
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
_G.origin = vim.api.nvim_get_current_buf()
_G.captured = nil
commands.add {
  name = "custom", range = true,
  cond = function(ctx) return ctx.bufnr == origin and ctx.has_range end,
  fn = function(data) captured = { buf = vim.api.nvim_get_current_buf(), data = data } end,
}
require("obsidian.picker").select = function(choices, _, callback)
  assert(vim.list_contains(choices, "custom"))
  _G.choose = callback
end
vim.cmd "1,2Obsidian"
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
choose { "custom" }
]]
  h.child_wait(child, "return captured ~= nil")
  local result = child.lua [[
return { captured.buf == origin, captured.data.range, captured.data.line1, captured.data.line2, captured.data.bang, captured.data.args, captured.data.fargs }
]]
  eq({ true, 2, 1, 2, false, "", {} }, result)
end

T["menu rechecks conditions and deletion at selection time"] = function()
  child.lua [[
_G.enabled = true
_G.calls = 0
commands.add { name = "custom", cond = function() return enabled end, fn = function() calls = calls + 1 end }
require("obsidian.picker").select = function(_, _, callback) _G.choose = callback end
vim.cmd.Obsidian()
enabled = false
choose { "custom" }
]]
  h.child_wait(child, "return #errors == 1")
  child.lua [[
enabled = true
vim.cmd.Obsidian()
commands.del "custom"
choose { "custom" }
]]
  h.child_wait(child, "return #errors == 2")
  eq(0, child.lua_get "calls")
end

T["menu rejects a deleted buffer"] = function()
  child.lua [[
_G.calls = 0
commands.add { name = "custom", fn = function() calls = calls + 1 end }
require("obsidian.picker").select = function(_, _, callback) _G.choose = callback end
local origin = vim.api.nvim_get_current_buf()
vim.cmd.Obsidian()
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
vim.api.nvim_buf_delete(origin, { force = true })
choose { "custom" }
]]
  h.child_wait(child, "return #errors == 1")
  eq(0, child.lua_get "calls")
end

T["deprecated APIs support explicit handlers and lazy filename lookup"] = function()
  local result = child.lua [[
local calls, warnings = {}, {}
vim.notify_once = function(message) warnings[message] = true end
package.preload["obsidian.commands.extension"] = function()
  return function(data) calls[#calls + 1] = data.args end
end
require("obsidian").register_command("extension", { nargs = "?" })
commands.register("explicit", { func = function() calls[#calls + 1] = "explicit" end })
vim.cmd "Obsidian extension lazy"
vim.cmd.Obsidian "explicit"
assert(#errors == 0, vim.inspect(errors))
return { calls, #vim.tbl_keys(warnings) }
]]
  eq({ { "lazy", "explicit" }, 1 }, result)
end

T["deprecated note_action combines with a supplied condition"] = function()
  local result = child.lua [[
local enabled, calls = false, 0
commands.register("custom", {
  note_action = true,
  cond = function() return enabled end,
  func = function() calls = calls + 1 end,
})
local outside = has_command("custom")
vim.b.obsidian_buffer = true
local disabled = has_command("custom")
enabled = true
local inside = has_command("custom")
vim.cmd.Obsidian "custom"
return { outside, disabled, inside, calls }
]]
  eq({ false, false, true, 1 }, result)
end

T["inline builtin adapters delegate to actions and pickers"] = function()
  local result = child.lua [[
local actions = require "obsidian.actions"
local api = require "obsidian.api"
local picker = require "obsidian.picker"
local captured = {}
for _, name in ipairs { "search_tags", "unique_note", "link", "link_new", "toggle_checkbox", "extract_note" } do
  actions[name] = function(...) captured[name] = { ... } end
end
api.get_visual_selection = function() return { selection = "selected" } end
require("obsidian.footnotes").pick = function() captured.footnotes = true end
picker.grep_notes = function(opts) captured.search = opts end
commands.commands.tags.fn { fargs = { "one", "two" } }
commands.commands.unique_note.fn()
commands.commands.link.fn()
commands.commands.link_new.fn { args = "New note" }
commands.commands.toggle_checkbox.fn { line1 = 2, line2 = 4 }
commands.commands.extract_note.fn { args = "Extracted" }
commands.commands.footnotes.fn()
commands.commands.search.fn { args = "query" }
return captured
]]
  eq({
    search_tags = { { "one", "two" } },
    unique_note = {},
    link = { { selection = "selected" } },
    link_new = { "New note", { selection = "selected" } },
    toggle_checkbox = { 2, 4 },
    extract_note = { "Extracted" },
    footnotes = true,
    search = { query = "query" },
  }, result)
end

T["legacy commands and picker creation use inline handlers"] = function()
  local result = child.lua [[
commands.install_legacy()
local captured = {}
commands.commands.tags.fn = function(data) captured.tags = data.fargs end
commands.commands.new.fn = function(data) captured[#captured + 1] = data.args end
vim.cmd "ObsidianTags one two"
vim.cmd "ObsidianNew legacy"
require("obsidian.picker.mappings").new_note("picker")
return { captured.tags, captured[1], captured[2] }
]]
  eq({ { "one", "two" }, "legacy", "picker" }, result)
end

T["separate legacy user commands remain available"] = function()
  local result = child.lua [[
commands.install_legacy()
local called = false
package.loaded["obsidian.commands.today"] = function() called = true end
vim.cmd.ObsidianToday()
return { called, vim.fn.exists(":ObsidianToday") }
]]
  eq({ true, 2 }, result)
end

return T
