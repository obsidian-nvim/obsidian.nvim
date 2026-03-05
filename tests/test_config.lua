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

T["normalize"] = new_set()

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
  eq(true, tostring(err):match "Invalid 'link.style' option" ~= nil)
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
  eq(true, tostring(err):match "Invalid 'link.format' option" ~= nil)
end

return T
