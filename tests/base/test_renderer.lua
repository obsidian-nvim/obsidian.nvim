local renderer = require "obsidian.base.renderer"
local Path = require "obsidian.path"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["renders table views as Markdown"] = function()
  local root = Path.temp { suffix = "-base-renderer" }
  root:mkdir { parents = true }
  Obsidian = { dir = root, opts = vim.deepcopy(require "obsidian.config.default") }

  local lines = renderer.render {
    type = "table",
    columns = {
      { key = "file.name", label = "File" },
      { key = "note.status", label = "Status" },
    },
    rows = {
      {
        path = tostring(root / "Projects" / "A.md"),
        values = { ["file.name"] = "A", ["note.status"] = "Doing | blocked" },
      },
    },
  }

  eq({
    "| File | Status |",
    "| --- | --- |",
    "| [[Projects/A\\|A]] | Doing \\| blocked |",
  }, lines)
end

T["renders list views as Markdown"] = function()
  local root = Path.temp { suffix = "-base-renderer" }
  root:mkdir { parents = true }
  Obsidian = { dir = root, opts = vim.deepcopy(require "obsidian.config.default") }

  local lines = renderer.render {
    type = "list",
    columns = {
      { key = "file.name", label = "File" },
      { key = "note.tags", label = "Tags" },
    },
    rows = {
      {
        path = tostring(root / "A.md"),
        values = { ["file.name"] = "A", ["note.tags"] = { "one", "two" } },
      },
    },
  }

  eq({ "- [[A|A]] — one, two" }, lines)
end

T["renders an empty list"] = function()
  eq({ "- _No results_" }, renderer.render { type = "list", columns = {}, rows = {} })
end

return T
