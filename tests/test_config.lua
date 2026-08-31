local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local config = require "obsidian.config"
local defaults = require "obsidian.config.default"

---@param opts obsidian.config
---@return obsidian.config.Internal
local function normalize(opts)
  opts = opts or {}
  opts.legacy_commands = false
  return config.normalize(opts, vim.deepcopy(defaults))
end

T["enums"] = new_set()
T["normalize"] = new_set()
T["setup"] = new_set()

T["normalize"]["should migrate completion.preferred_link_style to link.style"] = function()
  local opts = normalize {
    completion = {
      preferred_link_style = "markdown",
    },
  }

  eq("markdown", opts.link.style)
  eq(nil, opts.completion.preferred_link_style)
end

T["normalize"]["should migrate preferred_link_style to link.style"] = function()
  local opts = normalize {
    preferred_link_style = "markdown",
  }

  eq("markdown", opts.link.style)
  eq(nil, opts.preferred_link_style)
end

T["normalize"]["should prefer explicit link.style over deprecated preferred_link_style"] = function()
  local opts = normalize {
    preferred_link_style = "markdown",
    link = {
      style = "wiki",
    },
  }

  eq("wiki", opts.link.style)
end

T["normalize"]["should validate link.style"] = function()
  local ok, err = pcall(normalize, {
    link = {
      style = "invalid",
    },
  })

  eq(false, ok)
  eq(true, tostring(err):match "link.style: expected one of" ~= nil)
end

T["normalize"]["should allow function for link.style"] = function()
  local opts = normalize {
    link = {
      style = function(link_opts)
        return "[[" .. tostring(link_opts.path) .. "]]"
      end,
    },
  }

  eq("function", type(opts.link.style))
end

T["normalize"]["should validate link.format"] = function()
  local ok, err = pcall(normalize, {
    link = {
      format = "invalid",
    },
  })

  eq(false, ok)
  eq(true, tostring(err):match "link.format: expected one of" ~= nil)
end

T["normalize"]["should validate picker.name during setup"] = function()
  local ok, err = pcall(normalize, {
    picker = {
      name = "snacks.nvim",
    },
  })

  eq(false, ok)
  eq(true, tostring(err):match "picker.name: expected one of" ~= nil)
  eq(true, tostring(err):match '"snacks.picker"' ~= nil)
end

T["normalize"]["should validate workspace overrides during setup"] = function()
  local ok, err = pcall(normalize, {
    workspaces = {
      {
        path = ".",
        overrides = {
          new_notes_location = "vault",
        },
      },
    },
  })

  eq(false, ok)
  eq(true, tostring(err):match "workspaces%[1%]%.overrides.new_notes_location" ~= nil)
end

T["setup"]["notifies instead of throwing for invalid configuration"] = function()
  local notifications = {}
  local original_notify = vim.notify
  local original_state = Obsidian
  local log = require "obsidian.log"
  local original_log_level = log._log_level
  local original_log_err = log.err
  log.set_level(vim.log.levels.TRACE)
  log.err = function(message, ...)
    vim.notify(string.format(message, ...), vim.log.levels.ERROR)
  end
  vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
  end

  local success, client = pcall(require("obsidian").setup, {
    picker = {
      name = "snacks.nvim",
    },
  })
  local failed_state = Obsidian

  vim.notify = original_notify
  Obsidian = original_state
  log.err = original_log_err
  log.set_level(original_log_level)

  eq(true, success)
  eq(nil, client)
  eq(nil, failed_state.opts)
  eq(true, failed_state._config_error:match "picker.name: expected one of" ~= nil)
  eq(1, #notifications)
  eq(vim.log.levels.ERROR, notifications[1].level)
  eq(true, notifications[1].message:match "obsidian.nvim did not finish setup" ~= nil)
end

T["normalize"]["should aggregate validation errors"] = function()
  local ok, err = pcall(normalize, {
    new_notes_location = "vault",
    picker = {
      name = "snacks.nvim",
    },
    daily_notes = {
      start_of_week = 7,
    },
  })

  err = tostring(err)
  eq(false, ok)
  eq(true, err:match "new_notes_location: expected one of" ~= nil)
  eq(true, err:match "picker.name: expected one of" ~= nil)
  eq(true, err:match "daily_notes.start_of_week: expected integer between 0 and 6" ~= nil)
end

return T
