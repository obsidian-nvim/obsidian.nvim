local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["config"] = new_set()

local function config_reports(state)
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

  local config = {}
  local in_config = false
  for _, report in ipairs(reports) do
    if report.kind == "start" then
      if report.message == "[Config]" then
        in_config = true
      elseif in_config then
        break
      end
    elseif in_config then
      config[#config + 1] = report
    end
  end
  return config
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

return T
