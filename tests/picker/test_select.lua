local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local function with_select(select_impl, fn)
  local original_select = vim.ui.select
  vim.ui.select = select_impl
  local ok, err = pcall(fn)
  vim.ui.select = original_select
  if not ok then
    error(err)
  end
end

T["default select wraps current vim.ui.select result in a list"] = function()
  local picker = require "obsidian.picker._default"
  local choices

  with_select(function(items, opts, on_choice)
    eq("Pick", opts.prompt)
    on_choice(items[2], 2)
  end, function()
    picker.select({ "one", "two" }, { prompt = "Pick" }, function(selected)
      choices = selected
    end)
  end)

  eq({ "two" }, choices)
end

T["default select accepts proposed list result"] = function()
  local picker = require "obsidian.picker._default"
  local choices

  with_select(function(items, _, on_choice)
    on_choice { items[1], items[2] }
  end, function()
    picker.select({ "one", "two" }, { allow_multiple = true }, function(selected)
      choices = selected
    end)
  end)

  eq({ "one", "two" }, choices)
end

return T
