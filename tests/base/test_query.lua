local base = require "obsidian.base"
local cache = require "obsidian.cache"
local helpers = require "tests.helpers"
local Path = require "obsidian.path"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      cache.shutdown()
    end,
    post_case = function()
      cache.shutdown()
    end,
  },
}

T["filters, evaluates formulas, sorts, and limits cached notes"] = function()
  local root = Path.temp { suffix = "-base-query" }
  local projects = root / "Projects"
  projects:mkdir { parents = true }
  helpers.write("---\npriority: 1\n---\n# A", root / "Projects" / "A.md")
  helpers.write("---\npriority: 2\n---\n# B", root / "Projects" / "B.md")
  helpers.write("---\npriority: 9\n---\n# Other", root / "Other.md")

  Obsidian = {
    dir = root,
    opts = vim.deepcopy(require "obsidian.config.default"),
  }
  cache.setup { enabled = true, backend = "memory" }
  helpers.wait(function()
    return cache.is_ready()
  end)

  local document = base.parse [[formulas:
  score: priority + 1
views:
  - type: table
    name: Ranked
    filters: file.inFolder("Projects")
    order: [file.name, formula.score]
    sort:
      - property: formula.score
        direction: DESC
    limit: 1]]
  local model, err = base.query.run(document, document.views[1])

  eq(nil, err)
  eq(1, #model.rows)
  eq("B", model.rows[1].values["file.name"])
  eq(3, model.rows[1].values["formula.score"])
end

return T
