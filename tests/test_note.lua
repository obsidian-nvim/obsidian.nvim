---@diagnostic disable: invisible, duplicate-set-field
local M = require "obsidian.note"
local T = dofile("tests/helpers.lua").temp_vault
local util = require "obsidian.util"
local api = require "obsidian.api"
local Path = require "obsidian.path"
local config = require "obsidian.config"

local new_set, eq, not_eq = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.no_equality

local default_note_creation_opts = {
  notes_subdir = config.notes_subdir,
  note_id_func = function(title)
    local id = ""
    if title ~= nil then
      id = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
    else
      for _ = 1, 4 do
        id = id .. string.char(math.random(65, 90))
      end
    end
    return id
  end,
  new_notes_location = config.new_notes_location,
}

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  notes_subdir = "/custom/path/to/zettels",
  note_id_func = function()
    return "hummus"
  end,
}

T["new"] = new_set()

T["new"]["should be able to be initialize directly"] = function()
  local note = M.new("FOO", { "foo", "foos" }, { "bar" })
  eq(note.id, "FOO")
  eq(note.aliases[1], "foo")
  eq(true, M.is_note_obj(note))
end

T["save"] = new_set()

T["save"]["should be able to save to file"] = function()
  local note = M.from_file "tests/fixtures/notes/foo.md"
  note:add_alias "Foo Bar"
  note:save { path = "./tests/fixtures/notes/foo_bar.md" }
end

T["save"]["should be able to save a note w/o frontmatter"] = function()
  local note = M.from_file "tests/fixtures/notes/note_without_frontmatter.md"
  note:save { path = "./tests/fixtures/notes/note_without_frontmatter_saved.md" }
end

T["save"]["should be able to save a new note"] = function()
  local note = M.new("FOO", {}, {}, "/tmp/" .. util.zettel_id() .. ".md")
  note:save()
end

T["add_alias"] = new_set()

T["add_alias"]["should be able to add an alias"] = function()
  local note = M.from_file "tests/fixtures/notes/foo.md"
  eq(#note.aliases, 2)
  note:add_alias "Foo Bar"
  eq(#note.aliases, 3)
end

T["from_file"] = new_set()

T["from_file"]["should work from a file"] = function()
  local note = M.from_file "tests/fixtures/notes/foo.md"
  eq(note.id, "foo")
  eq(note.aliases[1], "foo")
  eq(note.aliases[2], "Foo")
  eq(note:fname(), "foo.md")
  eq(true, note.has_frontmatter)
  assert(#note.tags == 0)
end

T["from_file"]["should be able to collect anchor links"] = function()
  local note = M.from_file("tests/fixtures/notes/note_with_a_bunch_of_headers.md", { collect_anchor_links = true })
  eq(note.id, "note_with_a_bunch_of_headers")
  not_eq(note.anchor_links, nil)
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, note.anchor_links["#header-1"])
  eq({
    anchor = "#sub-header-1-a",
    line = 7,
    header = "Sub header 1 A",
    level = 2,
    parent = note.anchor_links["#header-1"],
  }, note.anchor_links["#sub-header-1-a"])
  eq({
    anchor = "#header-2",
    line = 9,
    header = "Header 2",
    level = 1,
  }, note.anchor_links["#header-2"])
  eq({
    anchor = "#sub-header-2-a",
    line = 11,
    header = "Sub header 2 A",
    level = 2,
    parent = note.anchor_links["#header-2"],
  }, note.anchor_links["#sub-header-2-a"])
  eq({
    anchor = "#sub-header-3-a",
    line = 13,
    header = "Sub header 3 A",
    level = 2,
    parent = note.anchor_links["#header-2"],
  }, note.anchor_links["#sub-header-3-a"])
  eq({
    anchor = "#header-2#sub-header-3-a",
    line = 13,
    header = "Sub header 3 A",
    level = 2,
    parent = note.anchor_links["#header-2"],
  }, note.anchor_links["#header-2#sub-header-3-a"])
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, note:resolve_anchor_link "#header-1")
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, note:resolve_anchor_link "#Header 1")
end

T["from_file"]["should be able to resolve anchor links after the fact"] = function()
  local note = M.from_file("tests/fixtures/notes/note_with_a_bunch_of_headers.md", { collect_anchor_links = false })
  eq(note.id, "note_with_a_bunch_of_headers")
  eq(nil, note.anchor_links)
  eq({ anchor = "#header-1", line = 5, header = "Header 1", level = 1 }, note:resolve_anchor_link "#header-1")
end

T["from_file"]["should be able to collect blocks"] = function()
  local note = M.from_file("tests/fixtures/notes/note_with_a_bunch_of_blocks.md", { collect_blocks = true })
  not_eq(nil, note.blocks)
  eq({
    id = "^1234",
    line = 5,
    block = "This is a block ^1234",
  }, note.blocks["^1234"])
  eq({
    id = "^hello-world",
    line = 7,
    block = "And another block ^hello-world",
  }, note.blocks["^hello-world"])
end

T["from_file"]["should be able to collect blocks after the fact"] = function()
  local note = M.from_file("tests/fixtures/notes/note_with_a_bunch_of_blocks.md", { collect_blocks = false })
  eq(nil, note.blocks)
  eq({
    id = "^1234",
    line = 5,
    block = "This is a block ^1234",
  }, note:resolve_block "^1234")
  eq({
    id = "^1234",
    line = 5,
    block = "This is a block ^1234",
  }, note:resolve_block "#^1234")
end

T["from_file"]["should work from a README"] = function()
  local note = M.from_file "README.md"
  eq(note.id, "README")
  eq(#note.tags, 0)
  eq(note:fname(), "README.md")
  eq(false, note:should_save_frontmatter())
end

T["from_file"]["should work from a file w/o frontmatter"] = function()
  local note = M.from_file "tests/fixtures/notes/note_without_frontmatter.md"
  eq(note.id, "note_without_frontmatter")
  eq(note.title, "Hey there")
  eq(#note.aliases, 0)
  eq(#note.tags, 0)
  not_eq(note:fname(), nil)
  eq(false, note.has_frontmatter)
  eq(true, note:should_save_frontmatter())
end

T["from_file"]["should collect additional frontmatter metadata"] = function()
  local note = M.from_file "tests/fixtures/notes/note_with_additional_metadata.md"
  eq(note.id, "note_with_additional_metadata")
  eq(note.title, "Note (has additional metadata)")
  not_eq(note.metadata, nil)
  eq(note.metadata.foo, "bar")
  eq(
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
  note:save { path = "./tests/fixtures/notes/note_with_additional_metadata_saved.md" }
end

T["from_file"]["should be able to be read frontmatter that's formatted differently"] = function()
  local note = M.from_file "tests/fixtures/notes/note_with_different_frontmatter_format.md"
  eq(note.id, "note_with_different_frontmatter_format")
  eq(note.metadata, nil)
  eq(#note.aliases, 3)
  eq(note.aliases[1], "Amanda Green")
  eq(note.aliases[2], "Detective Green")
  eq(note.aliases[3], "Mandy")
  eq(note.title, "Detective")
end

T["should work from a file"] = function()
  local note = M.from_file_async "tests/fixtures/notes/foo.md"
  eq(note.id, "foo")
  eq(note.aliases[1], "foo")
  eq(note.aliases[2], "Foo")
  eq(note:fname(), "foo.md")
  eq(true, note.has_frontmatter)
  assert(#note.tags == 0)
end

T["_is_frontmatter_boundary()"] = function()
  eq(true, M._is_frontmatter_boundary "---")
  eq(true, M._is_frontmatter_boundary "----")
end

T["_get_note_creation_opts"] = new_set {
  hooks = {
    pre_case = function()
      Obsidian.opts.templates.customizations = {
        Zettel = zettelConfig,
      }
    end,
  },
}

T["_get_note_creation_opts"]["should not load customizations for non-existent templates"] = function()
  local spec = M._get_creation_opts { template = "zettel" }

  eq(spec.notes_subdir, Obsidian.opts.notes_subdir)
  eq(spec.note_id_func, Obsidian.opts.note_id_func)
  eq(spec.new_notes_location, Obsidian.opts.new_notes_location)
end

T["_get_note_creation_opts"]["should load customizations for existing template"] = function()
  local note = M.create { dir = api.templates_dir(), id = "zettel" }
  note:write()

  local spec = assert(M._get_creation_opts { template = "zettel" })

  eq(spec.notes_subdir, zettelConfig.notes_subdir)
  eq(spec.note_id_func, zettelConfig.note_id_func)
end

T["new_note_path"] = new_set()

T["new_note_path"]['should only append one ".md" at the end of the path'] = function()
  Obsidian.opts.note_path_func = function(spec)
    return (spec.dir / "foo-bar-123"):with_suffix ".md.md.md"
  end

  -- Okay to set `id` and `dir` to default values because `note_path_func` is set
  local path = M._generate_path(nil, "", Path:new())
  eq(Path:new() / "foo-bar-123.md", path)
end

T["resolve_title_id_path"] = new_set()
T["resolve_title_id_path"]["should parse a title that's a partial path and generate new ID"] = function()
  local title, id, path = M._resolve_title_id_path("notes/Foo", nil, nil, default_note_creation_opts)
  eq("Foo", title)
  eq("foo", id)
  eq(Path:new(Obsidian.dir) / "notes" / "foo.md", path)

  title, id, path = M._resolve_title_id_path("notes/New Title", nil, nil, default_note_creation_opts)
  eq("New Title", title)
  eq("new-title", id)
  eq(Path:new(Obsidian.dir) / "notes" / "new-title.md", path)
end

T["resolve_title_id_path"]["should interpret relative directories relative to vault root."] = function()
  local title, id, path = M._resolve_title_id_path("Foo", nil, "new-notes", default_note_creation_opts)
  eq(title, "Foo")
  eq(id, "foo")
  eq(path, Path:new(Obsidian.dir) / "new-notes" / "foo.md")
end

T["resolve_title_id_path"]["should parse an ID that's a path"] = function()
  local title, id, path = M._resolve_title_id_path("Foo", "notes/1234-foo", nil, default_note_creation_opts)
  eq(title, "Foo")
  eq(id, "1234-foo")
  eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "1234-foo.md"))
end

T["resolve_title_id_path"]["should parse a title that's an exact path"] = function()
  local title, id, path = M._resolve_title_id_path("notes/foo.md", nil, nil, default_note_creation_opts)
  eq(title, "foo")
  eq(id, "foo")
  eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "foo.md"))
end

T["resolve_title_id_path"]["should ignore boundary whitespace when parsing a title"] = function()
  local title, id, path = M._resolve_title_id_path("notes/Foo  ", nil, nil, default_note_creation_opts)
  eq(title, "Foo")
  eq(id, "foo")
  eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "foo.md"))
end

T["resolve_title_id_path"]["should keep whitespace within a path when parsing a title"] = function()
  local title, id, path = M._resolve_title_id_path("notes/Foo Bar.md", nil, nil, default_note_creation_opts)
  eq(title, "Foo Bar")
  eq(id, "Foo Bar")
  eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "Foo Bar.md"))
end

T["resolve_title_id_path"]["should keep allow decimals in ID"] = function()
  local title, id, path = M._resolve_title_id_path("Title", "johnny.decimal", "notes", default_note_creation_opts)
  eq(title, "Title")
  eq(id, "johnny.decimal")
  eq(tostring(Path.new(Obsidian.dir) / "notes" / "johnny.decimal.md"), tostring(path))
end

T["resolve_title_id_path"]["should generate a new id when the title is just a folder"] = function()
  local title, id, path = M._resolve_title_id_path("notes/", nil, nil, default_note_creation_opts)
  eq(title, nil)
  eq(#id, 4)
  eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / (id .. ".md")))
end

T["resolve_title_id_path"]["should respect configured 'note_path_func'"] = function()
  Obsidian.opts.note_path_func = function(spec)
    return (spec.dir / "foo-bar-123"):with_suffix ".md"
  end

  local title, id, path = M._resolve_title_id_path("New Note", nil, nil, default_note_creation_opts)
  eq("New Note", title)
  eq("new-note", id)
  eq(Path:new(Obsidian.dir) / "foo-bar-123.md", path)
end

T["resolve_title_id_path"]["should ensure result of 'note_path_func' always has '.md' suffix"] = function()
  Obsidian.opts.note_path_func = function(spec)
    return spec.dir / "foo-bar-123"
  end

  local title, id, path = M._resolve_title_id_path("New Note", nil, nil, default_note_creation_opts)
  eq("New Note", title)
  eq("new-note", id)
  eq(Path:new(Obsidian.dir) / "foo-bar-123.md", path)
end

T["resolve_title_id_path"]["should ensure result of 'note_path_func' is always an absolute path and within provided directory"] = function()
  Obsidian.opts.note_path_func = function(_)
    return "foo-bar-123.md"
  end

  (Obsidian.dir / "notes"):mkdir { exist_ok = true }

  local title, id, path = M._resolve_title_id_path("New Note", nil, Obsidian.dir / "notes", default_note_creation_opts)
  eq("New Note", title)
  eq("new-note", id)
  eq(Path:new(Obsidian.dir) / "notes" / "foo-bar-123.md", path)
end

return T
