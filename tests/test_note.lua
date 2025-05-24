---@diagnostic disable: invisible

local Note = require "obsidian.note"
local util = require "obsidian.util"
local async = require "plenary.async"

describe("Note.new()", function()
  it("should be able to be initialize directly", function()
    local note = Note.new("FOO", { "foo", "foos" }, { "bar" })
    MiniTest.expect.equality(note.id, "FOO")
    MiniTest.expect.equality(note.aliases[1], "foo")
    MiniTest.expect.equality(true, Note.is_note_obj(note))
  end)
end)

describe("Note.from_file()", function()
  it("should work from a file", function()
    local note = Note.from_file "test/fixtures/notes/foo.md"
    MiniTest.expect.equality(note.id, "foo")
    MiniTest.expect.equality(note.aliases[1], "foo")
    MiniTest.expect.equality(note.aliases[2], "Foo")
    MiniTest.expect.equality(note:fname(), "foo.md")
    MiniTest.expect.equality(true, note.has_frontmatter)
    assert(#note.tags == 0)
  end)

  it("should be able to collect anchor links", function()
    local note = Note.from_file("test/fixtures/notes/note_with_a_bunch_of_headers.md", { collect_anchor_links = true })
    MiniTest.expect.equality(note.id, "note_with_a_bunch_of_headers")
    MiniTest.expect.no_equality(note.anchor_links, nil)

    MiniTest.expect.equality({
      anchor = "#header-1",
      line = 5,
      header = "Header 1",
      level = 1,
    }, note.anchor_links["#header-1"])

    MiniTest.expect.equality({
      anchor = "#sub-header-1-a",
      line = 7,
      header = "Sub header 1 A",
      level = 2,
      parent = note.anchor_links["#header-1"],
    }, note.anchor_links["#sub-header-1-a"])

    MiniTest.expect.equality({
      anchor = "#header-2",
      line = 9,
      header = "Header 2",
      level = 1,
    }, note.anchor_links["#header-2"])

    MiniTest.expect.equality({
      anchor = "#sub-header-2-a",
      line = 11,
      header = "Sub header 2 A",
      level = 2,
      parent = note.anchor_links["#header-2"],
    }, note.anchor_links["#sub-header-2-a"])

    MiniTest.expect.equality({
      anchor = "#sub-header-3-a",
      line = 13,
      header = "Sub header 3 A",
      level = 2,
      parent = note.anchor_links["#header-2"],
    }, note.anchor_links["#sub-header-3-a"])

    MiniTest.expect.equality({
      anchor = "#header-2#sub-header-3-a",
      line = 13,
      header = "Sub header 3 A",
      level = 2,
      parent = note.anchor_links["#header-2"],
    }, note.anchor_links["#header-2#sub-header-3-a"])

    MiniTest.expect.equality({
      anchor = "#header-1",
      line = 5,
      header = "Header 1",
      level = 1,
    }, note:resolve_anchor_link "#header-1")

    MiniTest.expect.equality({
      anchor = "#header-1",
      line = 5,
      header = "Header 1",
      level = 1,
    }, note:resolve_anchor_link "#Header 1")
  end)

  it("should be able to resolve anchor links after the fact", function()
    local note = Note.from_file("test/fixtures/notes/note_with_a_bunch_of_headers.md", { collect_anchor_links = false })
    MiniTest.expect.equality(note.id, "note_with_a_bunch_of_headers")
    MiniTest.expect.equality(nil, note.anchor_links)
    MiniTest.expect.equality(
      { anchor = "#header-1", line = 5, header = "Header 1", level = 1 },
      note:resolve_anchor_link "#header-1"
    )
  end)

  it("should be able to collect blocks", function()
    local note = Note.from_file("test/fixtures/notes/note_with_a_bunch_of_blocks.md", { collect_blocks = true })
    MiniTest.expect.no_equality(nil, note.blocks)

    MiniTest.expect.equality({
      id = "^1234",
      line = 5,
      block = "This is a block ^1234",
    }, note.blocks["^1234"])

    MiniTest.expect.equality({
      id = "^hello-world",
      line = 7,
      block = "And another block ^hello-world",
    }, note.blocks["^hello-world"])
  end)

  it("should be able to collect blocks after the fact", function()
    local note = Note.from_file("test/fixtures/notes/note_with_a_bunch_of_blocks.md", { collect_blocks = false })
    MiniTest.expect.equality(nil, note.blocks)

    MiniTest.expect.equality({
      id = "^1234",
      line = 5,
      block = "This is a block ^1234",
    }, note:resolve_block "^1234")

    MiniTest.expect.equality({
      id = "^1234",
      line = 5,
      block = "This is a block ^1234",
    }, note:resolve_block "#^1234")
  end)

  it("should work from a README", function()
    local note = Note.from_file "README.md"
    MiniTest.expect.equality(note.id, "README")
    MiniTest.expect.equality(#note.tags, 0)
    MiniTest.expect.equality(note:fname(), "README.md")
    MiniTest.expect.equality(false, note:should_save_frontmatter())
  end)

  it("should work from a file w/o frontmatter", function()
    local note = Note.from_file "test/fixtures/notes/note_without_frontmatter.md"
    MiniTest.expect.equality(note.id, "note_without_frontmatter")
    MiniTest.expect.equality(note.title, "Hey there")
    MiniTest.expect.equality(#note.aliases, 0)
    MiniTest.expect.equality(#note.tags, 0)
    MiniTest.expect.no_equality(note:fname(), nil)
    MiniTest.expect.equality(false, note.has_frontmatter)
    MiniTest.expect.equality(true, note:should_save_frontmatter())
  end)

  it("should collect additional frontmatter metadata", function()
    local note = Note.from_file "test/fixtures/notes/note_with_additional_metadata.md"
    MiniTest.expect.equality(note.id, "note_with_additional_metadata")
    MiniTest.expect.no_equality(note.metadata, nil)
    MiniTest.expect.equality(note.metadata.foo, "bar")
    MiniTest.expect.equality(
      table.concat(note:frontmatter_lines(), "\n"),
      table.concat({
        "---",
        "id: note_with_additional_metadata",
        "aliases: []",
        "tags: []",
        "foo: bar",
        "---",
      }, "\n")
    )
    note:save { path = "./test/fixtures/notes/note_with_additional_metadata_saved.md" }
  end)

  it("should be able to be read frontmatter that's formatted differently", function()
    local note = Note.from_file "test/fixtures/notes/note_with_different_frontmatter_format.md"
    MiniTest.expect.equality(note.id, "note_with_different_frontmatter_format")
    MiniTest.expect.no_equality(note.metadata, nil)
    MiniTest.expect.equality(#note.aliases, 3)
    MiniTest.expect.equality(note.aliases[1], "Amanda Green")
    MiniTest.expect.equality(note.aliases[2], "Detective Green")
    MiniTest.expect.equality(note.aliases[3], "Mandy")
    MiniTest.expect.equality(note.title, "Detective")
  end)
end)

describe("Note.from_file_async()", function()
  it("should work from a file", function()
    async.util.block_on(function()
      local note = Note.from_file_async "test/fixtures/notes/foo.md"
      MiniTest.expect.equality(note.id, "foo")
      MiniTest.expect.equality(note.aliases[1], "foo")
      MiniTest.expect.equality(note.aliases[2], "Foo")
      MiniTest.expect.equality(note:fname(), "foo.md")
      MiniTest.expect.equality(true, note.has_frontmatter)
      assert(#note.tags == 0)
    end, 1000)
  end)
end)

describe("Note.from_file_with_contents_async()", function()
  it("should work from a file", function()
    async.util.block_on(function()
      local note, contents = Note.from_file_with_contents_async "test/fixtures/notes/foo.md"
      MiniTest.expect.equality(note.id, "foo")
      MiniTest.expect.equality(note.aliases[1], "foo")
      MiniTest.expect.equality(note.aliases[2], "Foo")
      MiniTest.expect.equality(note:fname(), "foo.md")
      MiniTest.expect.equality(true, note.has_frontmatter)
      assert(#note.tags == 0)
      MiniTest.expect.equality("---", contents[1])
    end, 1000)
  end)
end)

describe("Note:add_alias()", function()
  it("should be able to add an alias", function()
    local note = Note.from_file "test/fixtures/notes/foo.md"
    MiniTest.expect.equality(#note.aliases, 2)
    note:add_alias "Foo Bar"
    MiniTest.expect.equality(#note.aliases, 3)
  end)
end)

describe("Note.save()", function()
  it("should be able to save to file", function()
    local note = Note.from_file "test/fixtures/notes/foo.md"
    note:add_alias "Foo Bar"
    note:save { path = "./test/fixtures/notes/foo_bar.md" }
  end)

  it("should be able to save a note w/o frontmatter", function()
    local note = Note.from_file "test/fixtures/notes/note_without_frontmatter.md"
    note:save { path = "./test/fixtures/notes/note_without_frontmatter_saved.md" }
  end)

  it("should be able to save a new note", function()
    local note = Note.new("FOO", {}, {}, "/tmp/" .. util.zettel_id() .. ".md")
    note:save()
  end)
end)

describe("Note._is_frontmatter_boundary()", function()
  it("should be able to find a frontmatter boundary", function()
    MiniTest.expect.equality(true, Note._is_frontmatter_boundary "---")
    MiniTest.expect.equality(true, Note._is_frontmatter_boundary "----")
  end)
end)
