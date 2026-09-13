---Note actions shared by the graph's context menu and Lua callers.
local M = {}

---@class obsidian.graph.ActionContext
---@field node obsidian.graph.Node Server-resolved note node, not the current buffer.
---@field path string Absolute path of the target note.

---@class obsidian.graph.ActionOpts
---@field name string Unique action identifier.
---@field title string|fun(ctx: obsidian.graph.ActionContext): string
---@field cond? fun(ctx: obsidian.graph.ActionContext): boolean
---@field fn fun(ctx: obsidian.graph.ActionContext) Run on Neovim's main loop; throw on failure.

---@type obsidian.graph.ActionOpts[]
local actions = {}

---Register in menu order. Registrations survive graph server restarts.
---Duplicate names are rejected. The returned unregister function is idempotent.
---@param opts obsidian.graph.ActionOpts
---@return fun() unregister
function M.register(opts)
  vim.validate("name", opts.name, "string")
  assert(opts.name ~= "", "Action name must not be empty")
  vim.validate("title", opts.title, { "string", "function" })
  vim.validate("cond", opts.cond, "function", true)
  vim.validate("fn", opts.fn, "function")
  for _, action in ipairs(actions) do
    assert(action.name ~= opts.name, "Action already registered: " .. opts.name)
  end

  ---@type obsidian.graph.ActionOpts
  local action = vim.tbl_extend("force", {}, opts)
  actions[#actions + 1] = action
  return function()
    for i, registered in ipairs(actions) do
      if registered == action then
        table.remove(actions, i)
        return
      end
    end
  end
end

---@param ctx obsidian.graph.ActionContext
---@return { name: string, title: string }[]
function M.list(ctx)
  local out = {}
  for _, action in ipairs(actions) do
    if not action.cond or action.cond(ctx) then
      local title = type(action.title) == "function" and action.title(ctx) or action.title
      assert(type(title) == "string", "Action title must be a string: " .. action.name)
      out[#out + 1] = { name = action.name, title = title }
    end
  end
  return out
end

---@param name string
---@param ctx obsidian.graph.ActionContext
---@return boolean success
---@return string? err
function M.execute(name, ctx)
  for _, action in ipairs(actions) do
    if action.name == name then
      if action.cond and not action.cond(ctx) then
        return false, "Action unavailable"
      end
      action.fn(ctx)
      return true
    end
  end
  return false, "Action not found"
end

M.register {
  name = "open",
  title = "Open",
  fn = function(ctx)
    local ok, err = require("obsidian.core-plugins.graph").open_note_by_id(ctx.node.id)
    if not ok then
      error(err)
    end
  end,
}

M.register {
  name = "copy_path",
  title = "Copy path",
  fn = function(ctx)
    assert(vim.fn.has "clipboard" == 1, "No clipboard provider available")
    assert(vim.fn.setreg("+", ctx.path, "v") == 0, "Failed to copy note path")
  end,
}

return M
