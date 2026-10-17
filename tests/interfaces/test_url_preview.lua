local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["built-in URL preview is plain content and makes no network request"] = function()
  local result = h.child_await(
    child,
    [[
    local preview = require "obsidian.preview"
    local original_system = vim.system
    local requests = 0
    vim.system = function()
      requests = requests + 1
      error("URL preview must not start a process")
    end
    local spec = preview.url { url = "https://example.com/private?token=x" }
    local lines = vim.api.nvim_buf_get_lines(spec.buf, 0, -1, false)
    vim.system = original_system
    done { requests = requests, lines = lines, filetype = vim.bo[spec.buf].filetype }
    vim.api.nvim_buf_delete(spec.buf, { force = true })
  ]],
    { desc = "built-in URL preview" }
  )

  eq(0, result.requests)
  eq({
    "https://example.com/private?token=x",
    "",
    "Customize URL previews with resolvers.url_preview.",
    "See :Obsidian help resolvers",
  }, result.lines)
  eq("markdown", result.filetype)
end

T["custom URL content renders and invalid results fall back"] = function()
  local result = h.child_await(
    child,
    [[
    local preview = require "obsidian.preview"
    Obsidian.opts.resolvers.url_preview = function(ctx, done)
      done { lines = { "Preview: " .. ctx.url }, filetype = "text" }
    end
    local custom = preview.url { url = "https://example.com" }
    local custom_lines = vim.api.nvim_buf_get_lines(custom.buf, 0, -1, false)

    Obsidian.opts.resolvers.url_preview = function(_, done)
      done { lines = { "invalid", 42 } }
    end
    local fallback = preview.url { url = "https://invalid.example" }
    local fallback_lines = vim.api.nvim_buf_get_lines(fallback.buf, 0, -1, false)
    done { custom = custom_lines, filetype = vim.bo[custom.buf].filetype, fallback = fallback_lines }
    vim.api.nvim_buf_delete(custom.buf, { force = true })
    vim.api.nvim_buf_delete(fallback.buf, { force = true })
  ]],
    { desc = "custom and invalid URL preview results" }
  )

  eq({ "Preview: https://example.com" }, result.custom)
  eq("text", result.filetype)
  eq({
    "https://invalid.example",
    "",
    "Customize URL previews with resolvers.url_preview.",
    "See :Obsidian help resolvers",
  }, result.fallback)
end

T["late URL preview results are discarded after a replacement"] = function()
  local result = h.child_await(
    child,
    [[
    local preview = require "obsidian.preview"
    local callbacks = {}
    Obsidian.opts.resolvers.url_preview = function(ctx, done)
      callbacks[ctx.url] = done
    end
    local first = preview.url { url = "https://first.example" }
    local second = preview.url { url = "https://second.example" }
    callbacks["https://first.example"] { lines = { "stale" } }
    callbacks["https://second.example"] { lines = { "current" } }
    done {
      first = vim.api.nvim_buf_get_lines(first.buf, 0, -1, false),
      second = vim.api.nvim_buf_get_lines(second.buf, 0, -1, false),
    }
    vim.api.nvim_buf_delete(first.buf, { force = true })
    vim.api.nvim_buf_delete(second.buf, { force = true })
  ]],
    { desc = "URL preview replacement" }
  )

  eq("https://first.example", result.first[1])
  eq({ "current" }, result.second)
end

T["help command resolves the URL resolver documentation case-insensitively"] = function()
  local command = h.child_await(
    child,
    [[
    local api = require "obsidian.api"
    local original_docs_dir = api.docs_dir
    local original_cmd = vim.cmd
    api.docs_dir = function()
      return require("obsidian.path").new(vim.fn.getcwd()) / "docs"
    end
    vim.cmd = function(value)
      _G.help_command = value
    end
    require("obsidian.commands.help") { args = "resolvers" }
    vim.cmd = original_cmd
    api.docs_dir = original_docs_dir
    done(help_command)
  ]],
    { desc = "resolver docs help route" }
  )

  eq("edit " .. vim.fn.fnameescape(vim.fs.joinpath(vim.fn.getcwd(), "docs", "Resolvers.md")), command)
end

T["URL resolver errors are logged once and use fallback content"] = function()
  local result = h.child_await(
    child,
    [[
    local preview = require "obsidian.preview"
    local log = require "obsidian.log"
    local original_err = log.err
    local errors = 0
    log.err = function()
      errors = errors + 1
    end
    Obsidian.opts.resolvers.url_preview = function(_, done)
      done(nil, "resolver failed")
    end
    local spec = preview.url { url = "https://error.example" }
    local lines = vim.api.nvim_buf_get_lines(spec.buf, 0, -1, false)
    log.err = original_err
    done { errors = errors, lines = lines }
    vim.api.nvim_buf_delete(spec.buf, { force = true })
  ]],
    { desc = "URL resolver failure fallback" }
  )

  eq(1, result.errors)
  eq("https://error.example", result.lines[1])
  eq("See :Obsidian help resolvers", result.lines[4])
end

return T
