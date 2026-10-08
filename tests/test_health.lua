local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["config"] = new_set()

local function section_reports(section, state, term_program)
  local reports = {}
  local original_health = {}
  for _, kind in ipairs { "start", "info", "ok", "warn", "error" } do
    original_health[kind] = vim.health[kind]
    vim.health[kind] = function(message)
      reports[#reports + 1] = { kind = kind, message = message }
    end
  end

  local original_state = Obsidian
  local original_term_program = vim.env.TERM_PROGRAM
  Obsidian = state
  vim.env.TERM_PROGRAM = term_program
  package.loaded["obsidian.health"] = nil
  local success, check_error = pcall(require("obsidian.health").check)
  package.loaded["obsidian.health"] = nil
  Obsidian = original_state
  vim.env.TERM_PROGRAM = original_term_program
  for kind, fn in pairs(original_health) do
    vim.health[kind] = fn
  end
  assert(success, check_error)

  local section_output = {}
  local in_section = false
  for _, report in ipairs(reports) do
    if report.kind == "start" then
      if report.message == "[" .. section .. "]" then
        in_section = true
      elseif in_section then
        break
      end
    elseif in_section then
      section_output[#section_output + 1] = report
    end
  end
  return section_output
end

local function config_reports(state)
  return section_reports("Config", state)
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

T["images"] = new_set()

local function setup_state(img_enabled)
  local opts = vim.deepcopy(require "obsidian.config.default")
  opts.img.enabled = img_enabled
  return {
    _setup_called = true,
    opts = opts,
    dir = ".",
    workspaces = {},
  }
end

T["images"]["reports when setup has not completed"] = function()
  local reports = section_reports("Images", nil)
  eq(1, #reports)
  eq("info", reports[1].kind)
  eq("setup() has not completed; image configuration was not checked", reports[1].message)
end

T["images"]["reports when native images are disabled"] = function()
  local reports = section_reports("Images", setup_state(false))
  eq(1, #reports)
  eq("ok", reports[1].kind)
  eq("disabled", reports[1].message)
end

T["images"]["warns that WezTerm cannot render inline images"] = function()
  local reports = section_reports("Images", setup_state(true), "WezTerm")
  eq("warn", reports[#reports].kind)
  eq(true, reports[#reports].message:find("inline image rendering will not work", 1, true) ~= nil)
  eq(true, reports[#reports].message:find("wezterm/wezterm/pull/7924", 1, true) ~= nil)
end

T["images"]["does not emit the WezTerm warning for other terminals"] = function()
  local reports = section_reports("Images", setup_state(true), "kitty")
  for _, report in ipairs(reports) do
    eq(false, report.message:find("WezTerm", 1, true) ~= nil)
  end
end

return T
