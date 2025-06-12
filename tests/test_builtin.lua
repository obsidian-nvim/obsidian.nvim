local builtin = require "obsidian.builtin"

describe("util.wiki_link_id_prefix()", function()
  it("should work without an anchor link", function()
    MiniTest.expect.equality(
      "[[123-foo|Foo]]",
      builtin.wiki_link_id_prefix { path = "123-foo.md", id = "123-foo", label = "Foo" }
    )
  end)

  it("should work with an anchor link", function()
    MiniTest.expect.equality(
      "[[123-foo#heading|Foo ❯ Heading]]",
      builtin.wiki_link_id_prefix {
        path = "123-foo.md",
        id = "123-foo",
        label = "Foo",
        anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
      }
    )
  end)
end)

describe("util.wiki_link_path_prefix()", function()
  it("should work without an anchor link", function()
    MiniTest.expect.equality(
      "[[123-foo.md|Foo]]",
      builtin.wiki_link_path_prefix { path = "123-foo.md", id = "123-foo", label = "Foo" }
    )
  end)

  it("should work with an anchor link and header", function()
    MiniTest.expect.equality(
      "[[123-foo.md#heading|Foo ❯ Heading]]",
      builtin.wiki_link_path_prefix {
        path = "123-foo.md",
        id = "123-foo",
        label = "Foo",
        anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
      }
    )
  end)
end)

describe("util.wiki_link_path_only()", function()
  it("should work without an anchor link", function()
    MiniTest.expect.equality(
      "[[123-foo.md]]",
      builtin.wiki_link_path_only { path = "123-foo.md", id = "123-foo", label = "Foo" }
    )
  end)

  it("should work with an anchor link", function()
    MiniTest.expect.equality(
      "[[123-foo.md#heading]]",
      builtin.wiki_link_path_only {
        path = "123-foo.md",
        id = "123-foo",
        label = "Foo",
        anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
      }
    )
  end)
end)

describe("util.markdown_link()", function()
  it("should work without an anchor link", function()
    MiniTest.expect.equality(
      "[Foo](123-foo.md)",
      builtin.markdown_link { path = "123-foo.md", id = "123-foo", label = "Foo" }
    )
  end)

  it("should work with an anchor link", function()
    MiniTest.expect.equality(
      "[Foo ❯ Heading](123-foo.md#heading)",
      builtin.markdown_link {
        path = "123-foo.md",
        id = "123-foo",
        label = "Foo",
        anchor = { anchor = "#heading", header = "Heading", level = 1, line = 1 },
      }
    )
  end)

  it("should URL-encode paths", function()
    MiniTest.expect.equality(
      "[Foo](notes/123%20foo.md)",
      builtin.markdown_link { path = "notes/123 foo.md", id = "123-foo", label = "Foo" }
    )
  end)
end)
