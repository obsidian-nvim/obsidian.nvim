local Path = require "obsidian.path"
local child = MiniTest.new_child_neovim()

local M = {}

local wait_timeout = 3000
local wait_interval = 20
local async_id = 0

---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
local function wait_opts(opts)
  opts = opts or {}
  return opts.timeout or wait_timeout, opts.interval or wait_interval, opts.desc or "condition"
end

---Wait in the parent test Neovim until predicate returns true.
---@param predicate fun(): boolean
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.wait = function(predicate, opts)
  local timeout, interval, desc = wait_opts(opts)
  local ok = vim.wait(timeout, predicate, interval, false)
  assert(ok, ("Timed out after %dms waiting for %s"):format(timeout, desc))
end

---Wait in a child Neovim until a Lua predicate body returns true.
---The predicate is executed as the body of a function, so it must `return` a boolean.
---@param child_neovim table
---@param predicate_lua string
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.child_wait = function(child_neovim, predicate_lua, opts)
  local timeout, interval, desc = wait_opts(opts)
  child_neovim.lua(([[
    local ok = vim.wait(%d, function()
      %s
    end, %d, false)
    assert(ok, %q)
  ]]):format(timeout, predicate_lua, interval, ("Timed out after %dms waiting for %s"):format(timeout, desc)))
end

---Run child Lua that calls `done(...)` asynchronously and return the callback values.
---@param child_neovim table
---@param body_lua string
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
---@return any ...
M.child_await = function(child_neovim, body_lua, opts)
  local timeout, interval, desc = wait_opts(opts)
  async_id = async_id + 1
  local key = "_obsidian_test_async_" .. async_id
  return child_neovim.lua(([[
    local state = { done = false, values = vim.F.pack_len() }
    _G[%q] = state
    local function done(...)
      state.values = vim.F.pack_len(...)
      state.done = true
    end

    %s

    local ok = vim.wait(%d, function()
      return state.done
    end, %d, false)
    _G[%q] = nil
    assert(ok, %q)
    return unpack(state.values, 1, state.values.n)
  ]]):format(key, body_lua, timeout, interval, key, ("Timed out after %dms waiting for %s"):format(timeout, desc)))
end

---@param child_neovim table
---@param expected string|obsidian.Path
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.child_wait_for_buf_name = function(child_neovim, expected, opts)
  expected = tostring(expected)
  opts = opts or {}
  opts.desc = opts.desc or ("buffer name " .. expected)
  M.child_wait(
    child_neovim,
    ("return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(%q)"):format(expected),
    opts
  )
end

---@param child_neovim table
---@param path string|obsidian.Path
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.child_wait_for_path = function(child_neovim, path, opts)
  path = tostring(path)
  opts = opts or {}
  opts.desc = opts.desc or ("path " .. path)
  M.child_wait(child_neovim, ("return vim.uv.fs_stat(%q) ~= nil"):format(path), opts)
end

---@param child_neovim table
---@param bufnr integer
---@param lnum integer 0-indexed
---@param expected string
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.child_wait_for_line = function(child_neovim, bufnr, lnum, expected, opts)
  opts = opts or {}
  opts.desc = opts.desc or ("line " .. lnum .. " in buffer " .. bufnr)
  M.child_wait(
    child_neovim,
    ("local line = vim.api.nvim_buf_get_lines(%d, %d, %d, false)[1]; return line == %q"):format(
      bufnr,
      lnum,
      lnum + 1,
      expected
    ),
    opts
  )
end

---@param child_neovim table
---@param client_name string
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
M.child_wait_for_lsp_client = function(child_neovim, client_name, opts)
  opts = opts or {}
  opts.desc = opts.desc or ("LSP client " .. client_name)
  M.child_wait(child_neovim, ("return #vim.lsp.get_clients({ name = %q }) > 0"):format(client_name), opts)
end

---@param child_neovim table
---@param client_name string
---@param method string
---@param params_lua string Lua expression for request params.
---@param opts { timeout: integer|?, interval: integer|?, desc: string|? }|?
---@return any result
M.child_lsp_request = function(child_neovim, client_name, method, params_lua, opts)
  opts = opts or {}
  opts.desc = opts.desc or (method .. " response")
  local out = M.child_await(
    child_neovim,
    ([=[
      local clients = vim.lsp.get_clients { name = %q }
      local client = assert(clients[1], "LSP client not attached: %s")
      client.request(%q, %s, function(err, result)
        if err then
          done({ error = vim.inspect(err) })
        else
          done({ result = result or {} })
        end
      end, 0)
    ]=]):format(client_name, client_name, method, params_lua),
    opts
  )
  if out.error then
    error(out.error)
  end
  return out.result
end

---Return test set and child instance
---@param hooks { pre_case: string|?, post_case: string|? }|?
M.child_vault = function(hooks)
  hooks = hooks or {}
  return MiniTest.new_set {
    hooks = {
      pre_case = function()
        child.restart { "-u", "scripts/minimal_init.lua" }
        child.lua [[
local Path = require "obsidian.path"
local dir = Path.temp { suffix = "-obsidian" }
dir:mkdir { parents = true }
local obsidian_dir = dir / ".obsidian"
obsidian_dir:mkdir()
local templates_dir = dir / "templates"
templates_dir:mkdir()
require("obsidian").setup {
  legacy_commands = false,
  workspaces = { {
    path = tostring(dir),
  } },
  templates = {
    folder = "templates",
  },
  footer = {
    enabled = false,
  },
  log_level = vim.log.levels.WARN,
}
        ]]
        if hooks.pre_case then
          child.lua(hooks.pre_case)
        end
        child.Obsidian = {}

        -- TODO: reconstruct the Obsidian vars
        child.Obsidian.dir = Path.new(child.lua_get("Obsidian.dir").filename)
      end,
      post_case = function()
        if hooks.post_case then
          child.lua(hooks.post_case)
        end
        child.lua [[
if Obsidian and Obsidian.dir then
  vim.fn.delete(tostring(Obsidian.dir), "rf")
end
        ]]
        child.stop()
      end,
    },
  },
    child
end

M.temp_vault = MiniTest.new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        legacy_commands = false,
        workspaces = { {
          path = tostring(dir),
        } },
        templates = {
          folder = "templates",
        },
        log_level = vim.log.levels.WARN,
      }

      Path.new(dir / "templates"):mkdir()
    end,
    post_case = function()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

M.write = function(str, path)
  vim.fn.writefile(vim.split(str, "\n"), tostring(path))
end

M.read = function(path)
  return vim.fn.readfile(tostring(path))
end

M.mock_vault_contents = function(dir, contents)
  local cfg_dir = dir / ".obsidian"
  cfg_dir:mkdir()
  local files = {}
  for rel_path, content in pairs(contents) do
    local path = dir / rel_path
    local parent = path:parent()
    if parent then
      parent:mkdir { parents = true }
    end
    files[rel_path] = tostring(path)
    M.write(content, path)
  end
  return files
end

M.child_mock_vault_contents = function(child_neovim, contents)
  return M.mock_vault_contents(child_neovim.Obsidian.dir, contents)
end

M.child_setup_cache = function(child_neovim, opts)
  opts = opts or { enabled = true, backend = "memory" }
  child_neovim.lua(
    [[
local opts = ...
local cache = require "obsidian.cache"
cache.setup(opts)
if opts.enabled ~= false then
  local ok = vim.wait(3000, function()
    return cache.is_ready()
  end, 20, false)
  assert(ok, "Timed out after 3000ms waiting for cache ready")
end
    ]],
    { opts }
  )
end

return M
