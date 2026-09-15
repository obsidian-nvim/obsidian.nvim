local header = require "obsidian.parse.header"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["parse handles ATX headings"] = function()
  eq({ header = "Hello World", level = 2, anchor = "#hello-world" }, header.parse "## Hello World")
  eq({ header = "Hello World", level = 1, anchor = "#hello-world" }, header.parse "# Hello World ")
end

T["parse rejects non-headings"] = function()
  eq(nil, header.parse "Hello World")
  eq(nil, header.parse "#Hello World")
end

T["to_anchor normalizes heading labels"] = function()
  eq("#hello-world", header.to_anchor "# Hello, World!")
  eq("#hello-world-123", header.to_anchor "# Hello, World! 123")
  eq("#hello_world", header.to_anchor "# Hello_World")
  eq("#hello--world", header.to_anchor "# Hello  World!")
end

T["normalize_anchor adds one leading marker"] = function()
  eq("#hello-world", header.normalize_anchor "Hello World")
  eq("#hello-world", header.normalize_anchor "#Hello World")
  eq("#parent#child", header.normalize_anchor "##Parent#Child")
end

return T
