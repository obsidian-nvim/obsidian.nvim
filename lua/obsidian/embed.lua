local async = require "obsidian.async"
local link = require "obsidian.link"
local parse_refs = require "obsidian.parse.refs"

local M = {}

local NAMESPACE = "ObsidianEmbed"
local providers = {}
local provider_names = {}
local attached = {}
local dependencies = {}
local global_setup = false
local builtins_registered = false

---@class obsidian.embed.Context
---@field bufnr integer
---@field source_path string
---@field target_path string
---@field ref obsidian.parse.Ref
---@field stack string[]
---@field depth integer

---@class obsidian.embed.Result
---@field lines string[]|table[]
---@field dependencies? string[]
---@field vault_wide? boolean
---@field error? string

---@class obsidian.embed.Provider
---@field name string
---@field extensions? string[]
---@field can_render? fun(ctx: obsidian.embed.Context): boolean
---@field render fun(ctx: obsidian.embed.Context): obsidian.embed.Result
---@field invalidate? fun(path: string)

local function ensure_builtins()
  if builtins_registered then
    return
  end
  builtins_registered = true
  M.register(require "obsidian.embed.markdown")
  M.register(require "obsidian.base.embed")
end

---@param provider obsidian.embed.Provider
function M.register(provider)
  assert(type(provider) == "table", "embed provider must be a table")
  assert(type(provider.name) == "string" and provider.name ~= "", "embed provider requires a name")
  assert(type(provider.render) == "function", "embed provider requires a render function")

  if provider_names[provider.name] ~= nil then
    providers[provider_names[provider.name]] = provider
    return
  end
  providers[#providers + 1] = provider
  provider_names[provider.name] = #providers
end

---@param path string
---@return string
local function extension(path)
  return (path:match "%.([^./]+)$" or ""):lower()
end

---@param provider obsidian.embed.Provider
---@param ctx obsidian.embed.Context
---@return boolean
local function provider_matches(provider, ctx)
  if provider.can_render ~= nil and provider.can_render(ctx) then
    return true
  end
  local ext = extension(ctx.target_path)
  for _, candidate in ipairs(provider.extensions or {}) do
    if ext == candidate:lower():gsub("^%.", "") then
      return true
    end
  end
  return false
end

---@param path string
---@param stack string[]
---@return boolean
local function stack_contains(path, stack)
  path = vim.fs.normalize(path)
  for _, item in ipairs(stack) do
    if vim.fs.normalize(item) == path then
      return true
    end
  end
  return false
end

---@param source_path string
---@param ref obsidian.parse.Ref
---@param bufnr integer
---@return obsidian.embed.Result?
function M.render_ref(source_path, ref, bufnr)
  ensure_builtins()

  local target_path
  if ref.target:match "%.([^/]+)$" == nil then
    target_path = link.resolve_link_path(ref.target .. ".md", { source_path = source_path })
  end
  target_path = target_path or link.resolve_link_path(ref.target, { source_path = source_path })
  if target_path == nil then
    local target = ref.target:lower()
    if target:match "%.base$" or target:match "%.md$" or target:match "%.markdown$" or target:match "%.qmd$" then
      return { lines = {}, error = "target not found: " .. ref.target }
    end
    return nil
  end

  local stack = { source_path }
  if stack_contains(target_path, stack) then
    return { lines = {}, error = "cyclic embed: " .. ref.target }
  end

  ---@type obsidian.embed.Context
  local ctx = {
    bufnr = bufnr,
    source_path = source_path,
    target_path = target_path,
    ref = ref,
    stack = stack,
    depth = 1,
  }

  for _, provider in ipairs(providers) do
    if provider_matches(provider, ctx) then
      local ok, result = pcall(provider.render, ctx)
      if not ok then
        return { lines = {}, error = tostring(result), dependencies = { target_path } }
      end
      if type(result) ~= "table" then
        return { lines = {}, error = "provider returned an invalid result", dependencies = { target_path } }
      end
      result.dependencies = result.dependencies or { target_path }
      result.lines = result.lines or {}
      return result
    end
  end
  return nil
end

---@param line string
---@return table
local function virtual_line(line)
  if type(line) == "table" then
    return line
  end
  return { { tostring(line), "Normal" } }
end

---@param message string
---@return table
local function error_line(message)
  return { { "Embed preview: " .. message, "DiagnosticError" } }
end

---@param bufnr integer
local function rebuild(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local source_path = vim.api.nvim_buf_get_name(bufnr)
  if source_path == "" then
    return
  end

  local ns = vim.api.nvim_create_namespace(NAMESPACE)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  dependencies[bufnr] = { paths = {}, vault_wide = false }

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local fence
  for index, line_text in ipairs(lines) do
    local marker = line_text:match "^%s*(```+)" or line_text:match "^%s*(~~~+)"
    if marker ~= nil then
      local char = marker:sub(1, 1)
      if fence == nil then
        fence = char
      elseif fence == char then
        fence = nil
      end
    elseif fence == nil then
      local rendered = {}
      for _, ref in ipairs(parse_refs.extract(line_text, { row = index - 1 })) do
        if ref.embed then
          local result = M.render_ref(source_path, ref, bufnr)
          if result ~= nil then
            if #rendered > 0 then
              rendered[#rendered + 1] = { { "", "Normal" } }
            end
            if result.error ~= nil then
              rendered[#rendered + 1] = error_line(result.error)
            else
              for _, output_line in ipairs(result.lines or {}) do
                rendered[#rendered + 1] = virtual_line(output_line)
              end
            end
            for _, path in ipairs(result.dependencies or {}) do
              dependencies[bufnr].paths[vim.fs.normalize(path)] = true
            end
            dependencies[bufnr].vault_wide = dependencies[bufnr].vault_wide or result.vault_wide == true
          end
        end
      end

      if #rendered > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, ns, index - 1, 0, {
          virt_lines = rendered,
          virt_lines_above = false,
        })
      end
    end
  end
end

---@param bufnr integer?
function M.update(bufnr)
  bufnr = bufnr or 0
  rebuild(bufnr)
end

---@param bufnr integer?
function M.clear(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace(NAMESPACE), 0, -1)
  end
  dependencies[bufnr] = nil
end

---@param changed_path string
function M.notify_changed(changed_path)
  changed_path = vim.fs.normalize(changed_path)
  ensure_builtins()
  for _, provider in ipairs(providers) do
    if provider.invalidate ~= nil then
      pcall(provider.invalidate, changed_path)
    end
  end
  for bufnr, deps in pairs(dependencies) do
    if vim.api.nvim_buf_is_valid(bufnr) and (deps.vault_wide or deps.paths[changed_path]) then
      local target_buf = bufnr
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(target_buf) then
          rebuild(target_buf)
        end
      end)
    end
  end
end

local function ensure_global_setup()
  if global_setup then
    return
  end
  global_setup = true
  local group = vim.api.nvim_create_augroup("ObsidianEmbedDependencies", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(ev)
      if ev.file ~= nil and ev.file ~= "" then
        M.notify_changed(ev.file)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ObsidianCacheChanged",
    callback = function(ev)
      for _, path in ipairs((ev.data and ev.data.paths) or {}) do
        M.notify_changed(path)
      end
    end,
  })
end

---@param bufnr integer?
function M.start(bufnr)
  bufnr = bufnr or 0
  if attached[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  attached[bufnr] = true
  ensure_builtins()
  ensure_global_setup()

  local group = vim.api.nvim_create_augroup("ObsidianEmbed" .. bufnr, { clear = true })
  local throttled = async.throttle(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      rebuild(bufnr)
    end
  end, 200)

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      rebuild(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = bufnr,
    callback = throttled,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      attached[bufnr] = nil
      dependencies[bufnr] = nil
    end,
  })

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      rebuild(bufnr)
    end
  end)
end

M._providers = providers
M._dependencies = dependencies
M.NAMESPACE = NAMESPACE

return M
