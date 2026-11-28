local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["config"] = new_set()

local function section_reports(state, section)
  local reports = {}
  local original_health = {}
  for _, kind in ipairs { "start", "info", "ok", "warn", "error" } do
    original_health[kind] = vim.health[kind]
    vim.health[kind] = function(message)
      reports[#reports + 1] = { kind = kind, message = message }
    end
  end

  local original_state = Obsidian
  Obsidian = state
  package.loaded["obsidian.health"] = nil
  local success, check_error = pcall(require("obsidian.health").check)
  package.loaded["obsidian.health"] = nil
  Obsidian = original_state
  for kind, fn in pairs(original_health) do
    vim.health[kind] = fn
  end
  assert(success, check_error)

  local output = {}
  local in_section = false
  for _, report in ipairs(reports) do
    if report.kind == "start" then
      if report.message == ("[%s]"):format(section) then
        in_section = true
      elseif in_section then
        break
      end
    elseif in_section then
      output[#output + 1] = report
    end
  end
  return output
end

local function config_reports(state)
  return section_reports(state, "Config")
end

T["config"]["reports when setup has not been called"] = function()
  local reports = config_reports(nil)
  eq(1, #reports)
  eq("info", reports[1].kind)
  eq("setup() has not been called", reports[1].message)
end

T["config"]["reports passed validation after setup"] = function()
  local opts = vim.deepcopy(require "obsidian.config.default")
  local reports = config_reports {
    _setup_called = true,
    opts = opts,
    dir = ".",
    workspaces = {},
  }
  eq("ok", reports[1].kind)
  eq("configuration passed validation", reports[1].message)
end

T["config"]["reports validation issues after setup"] = function()
  local reports = config_reports {
    _setup_called = true,
    _user_opts = {
      picker = {
        name = "snacks.nvim",
      },
    },
  }
  eq(1, #reports)
  eq("error", reports[1].kind)
  eq(true, reports[1].message:match "picker.name: expected one of" ~= nil)
end

T["pickers"] = new_set()

T["pickers"]["recognizes a picker on a renamed runtime path without loading it"] = function()
  local runtime_dir = vim.fn.tempname()
  local module_path = runtime_dir .. "/lua/snacks/picker"
  vim.fn.mkdir(module_path, "p")
  vim.fn.writefile({ "error('health must not load this module')" }, module_path .. "/init.lua")
  local original_rtp = vim.o.runtimepath
  vim.opt.rtp:prepend(runtime_dir)

  local runtime = require "obsidian.runtime"
  local original_info = runtime.get_plugin_info
  runtime.get_plugin_info = function()
    return nil
  end
  local success, reports = pcall(section_reports, nil, "Pickers")
  runtime.get_plugin_info = original_info
  vim.o.runtimepath = original_rtp
  vim.fn.delete(runtime_dir, "rf")
  assert(success, reports)

  local snacks_found = false
  for _, report in ipairs(reports) do
    eq(false, report.kind == "warn")
    if report.kind == "ok" and report.message:find("snacks.nvim", 1, true) then
      snacks_found = true
    end
  end
  eq(true, snacks_found)
end

return T
