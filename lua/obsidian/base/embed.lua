local base = require "obsidian.base"
local query = require "obsidian.base.query"
local renderer = require "obsidian.base.renderer"

local M = {
  name = "bases",
  extensions = { "base" },
  invalidate = function()
    query.invalidate()
  end,
}

---@param path string
---@return string
local function read_source(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == vim.fs.normalize(path)
    then
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
  end
  local file, err = io.open(path, "r")
  if file == nil then
    error(err or ("failed to read " .. path))
  end
  local source = file:read "*a"
  file:close()
  return source
end

---@param diagnostics obsidian.base.Diagnostic[]
---@return string?
local function first_error(diagnostics)
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.severity == "error" then
      return diagnostic.message
    end
  end
end

---@param ctx obsidian.embed.Context
---@return obsidian.embed.Result
function M.render(ctx)
  local document, diagnostics = base.parse(read_source(ctx.target_path))
  if document == nil then
    return {
      lines = {},
      error = first_error(diagnostics) or "invalid Bases document",
      dependencies = { ctx.target_path },
    }
  end

  local view = base.select_view(document, ctx.ref.anchor)
  if view == nil then
    local message = ctx.ref.anchor and ('view not found: "' .. ctx.ref.anchor .. '"') or "no view defined"
    return { lines = {}, error = message, dependencies = { ctx.target_path } }
  end
  if view.type == nil then
    return { lines = {}, error = "view has no type", dependencies = { ctx.target_path } }
  elseif view.group_by ~= nil then
    return { lines = {}, error = "grouped views are not supported yet", dependencies = { ctx.target_path } }
  elseif next(view.summaries) ~= nil then
    return { lines = {}, error = "view summaries are not supported yet", dependencies = { ctx.target_path } }
  end

  local model, query_error = query.run(document, view)
  if model == nil then
    return { lines = {}, error = query_error or "failed to query view", dependencies = { ctx.target_path } }
  end
  local lines, render_error = renderer.render(model)
  if lines == nil then
    return { lines = {}, error = render_error or "failed to render view", dependencies = { ctx.target_path } }
  end

  return {
    lines = lines,
    dependencies = { ctx.target_path },
    vault_wide = true,
  }
end

return M
