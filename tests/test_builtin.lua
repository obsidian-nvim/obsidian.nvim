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

T["wiki_link_id_prefix"]["should work without an anchor link"] = function()
  eq("[[123-foo|Foo]]", builtin.wiki_link_id_prefix { path = "123-foo.md", id = "123-foo", label = "Foo" })
end

T["wiki_link_id_prefix"]["should work with an anchor link"] = function()
  eq(
    "[[123-foo#heading|Foo ❯ Heading]]",
    builtin.wiki_link_id_prefix {
      path = "123-foo.md",
      id = "123-foo",
      label = "Foo",
      anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
    }
  )
end

T["wiki_link_path_prefix"] = new_set()

T["wiki_link_path_prefix"]["should work without an anchor link"] = function()
  eq("[[123-foo.md|Foo]]", builtin.wiki_link_path_prefix { path = "123-foo.md", id = "123-foo", label = "Foo" })
end

T["wiki_link_path_prefix"]["should work with an anchor link and header"] = function()
  eq(
    "[[123-foo.md#heading|Foo ❯ Heading]]",
    builtin.wiki_link_path_prefix {
      path = "123-foo.md",
      id = "123-foo",
      label = "Foo",
      anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
    }
  )
end

T["wiki_link_path_only"] = new_set()

T["wiki_link_path_only"]["should work without an anchor link"] = function()
  eq("[[123-foo.md]]", builtin.wiki_link_path_only { path = "123-foo.md", id = "123-foo", label = "Foo" })
end

T["wiki_link_path_only"]["should work with an anchor link"] = function()
  eq(
    "[[123-foo.md#heading]]",
    builtin.wiki_link_path_only {
      path = "123-foo.md",
      id = "123-foo",
      label = "Foo",
      anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
    }
  )
end

T["markdown_link"] = new_set()

T["markdown_link"]["should work without an anchor link"] = function()
  eq("[Foo](123-foo.md)", builtin.markdown_link { path = "123-foo.md", id = "123-foo", label = "Foo" })
end

T["markdown_link"]["should work with an anchor link"] = function()
  eq(
    "[Foo ❯ Heading](123-foo.md#heading)",
    builtin.markdown_link {
      path = "123-foo.md",
      id = "123-foo",
      label = "Foo",
      anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
    }
  )
end

T["markdown_link"]["should URL-encode paths"] = function()
  eq("[Foo](notes/123%20foo.md)", builtin.markdown_link { path = "notes/123 foo.md", id = "123-foo", label = "Foo" })
end

return T
