local builtin = require "obsidian.builtin"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

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

return T
