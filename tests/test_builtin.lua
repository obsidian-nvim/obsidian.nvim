local builtin = require "obsidian.builtin"
local Path = require "obsidian.path"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["title_to_slug"] = new_set()

T["title_to_slug"]["should preserve UTF-8 slugs for common languages"] = function()
  local cases = {
    {
      input = "Hello, World 123!",
      expected = "hello-world-123",
    },
    {
      input = "Привет, мир",
      expected = "привет-мир",
    },
    {
      input = "你好 世界",
      expected = "你好-世界",
    },
    {
      input = "こんにちは 世界",
      expected = "こんにちは-世界",
    },
    {
      input = "مرحبا بالعالم",
      expected = "مرحبا-بالعالم",
    },
    {
      input = "नमस्ते दुनिया",
      expected = "नमस्ते-दुनिया",
    },
  }

  for _, case in ipairs(cases) do
    eq(case.expected, builtin.title_to_slug(case.input))
  end
end

T["title_to_slug"]["should fallback to zettel id when title cannot be slugified"] = function()
  local id = builtin.title_to_slug "!!!"
  eq(true, id:match "^%d+%-[A-Z][A-Z][A-Z][A-Z]$" ~= nil)
end

T["title_id"] = new_set()

T["title_id"]["should return unique title-based ID inside directory"] = function()
  local dir = Path.temp { suffix = "-obsidian" }
  dir:mkdir { parents = true }

  vim.fn.writefile({}, tostring((dir / "привет-мир"):with_suffix(".md", true)))

  local id = builtin.title_id("Привет мир", dir)
  eq("привет-мир-2", id)

  vim.fn.delete(tostring(dir), "rf")
end

T["wiki_link_id_prefix"] = new_set()

T["markdown_link"] = new_set()

T["markdown_link"]["should work without an anchor link"] = function()
  eq(
    "[Foo](123-foo.md)",
    builtin.markdown_link {
      path = "123-foo.md",
      label = "Foo",
    }
  )
end

T["markdown_link"]["should work with an anchor link"] = function()
  eq(
    "[Foo ❯ Heading](123-foo.md#heading)",
    builtin.markdown_link {
      path = "123-foo.md",
      label = "Foo",
      anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
    }
  )
end

return T
