local embed = require "obsidian.embed"
local helpers = require "tests.helpers"
local Path = require "obsidian.path"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      require("obsidian.cache").shutdown()
    end,
  },
}

local function virtual_text(bufnr)
  local marks =
    vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace(embed.NAMESPACE), 0, -1, { details = true })
  local lines = {}
  for _, mark in ipairs(marks) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      lines[#lines + 1] = line[1][1]
    end
  end
  return lines
end

T["renders an embedded Bases table"] = function()
  local root = Path.temp { suffix = "-base-embed" }
  root:mkdir { parents = true }
  Obsidian = {
    dir = root,
    opts = vim.deepcopy(require "obsidian.config.default"),
  }

  helpers.write("---\nstatus: active\n---\n# Task", root / "Task.md")
  helpers.write(
    [[filters: status == "active"
views:
  - type: table
    name: Tasks
    order:
      - file.name
      - status]],
    root / "Tasks.base"
  )

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, tostring(root / "Dashboard.md"))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "![[Tasks.base]]" })

  embed.update(bufnr)
  eq({
    "| file.name | status |",
    "| --- | --- |",
    "| [[Task\\|Task]] | active |",
  }, virtual_text(bufnr))
end

T["uses the embed anchor as the view name"] = function()
  local root = Path.temp { suffix = "-base-embed" }
  root:mkdir { parents = true }
  Obsidian = {
    dir = root,
    opts = vim.deepcopy(require "obsidian.config.default"),
  }

  helpers.write("# Note", root / "Note.md")
  helpers.write(
    [=[views:
  - type: table
    name: Table
    order: [file.name]
  - type: list
    name: List
    order: [file.name]]=],
    root / "Views.base"
  )

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, tostring(root / "Dashboard.md"))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "![[Views.base#List]]" })

  embed.update(bufnr)
  eq({ "- [[Note|Note]]" }, virtual_text(bufnr))
end

return T
