local M = require "obsidian.util"
local Path = require "obsidian.path"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        url_patterns = {
          {
            name = "URL-UUID",
            pattern = "uuid://[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+",
          },
          {
            name = "App",
            pattern = "app:///data/[a-zA-Z]+",
          },
        },
        workspaces = { {
          path = tostring(dir),
        } },
      }
    end,
  },
}

T["url_patterns"] = new_set()

T["url_patterns"]["should identify basic URLs"] = function()
  eq(true, M.is_url "https://example.com")
end

T["url_patterns"]["should identify semantic scholar API URLS"] = function()
  eq(true, M.is_url "https://api.semanticscholar.org/CorpusID:235829052")
end

T["url_patterns"]["should identify 'mailto' URLS"] = function()
  eq(true, M.is_url "mailto:mail@domain.com")
end

T["url_patterns"]["should identify URL-UUID"] = function()
  eq(true, M.is_url "uuid://abcdef-1234-5678-90af-abcdef")
end

T["url_patterns"]["should identify App-URL"] = function()
  eq(true, M.is_url "app:///data/testData")
end

T["url_patterns"]["should not identify unknown URL pattern"] = function()
  eq(false, M.is_url "unknown://some.unknown.url")
end

return T
