local M = require "obsidian.note"
local h = dofile "tests/helpers.lua"
local T = h.temp_vault
local api = require "obsidian.api"
local Path = require "obsidian.path"
local util = require "obsidian.util"

local new_set, eq, not_eq = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.no_equality

T["new"] = new_set()
T["new"]["should be able to be initialize directly"] = function()
  local note = M.new("FOO", { "foo", "foos" }, { "bar" })
  eq(note.id, "FOO")
  eq(note.aliases[1], "foo")
  eq(true, M.is_note_obj(note))
end

local function from_str(str, path, opts)
  return M.from_lines(vim.iter(vim.split(str, "\n")), path, opts)
end

local foo = [[---
id: foo
aliases:
 - foo
 - Foo
tags: []
---

# foo

This is some content.]]

-- local foo_bar = [[---
-- id: foo
-- aliases:
--   - foo
--   - Foo
--   - Foo Bar
-- tags: []
-- ---
--
-- # foo
--
-- This is some content.]]

-- T["save"]["should be able to save to file"] = function()
--   local note = from_str(foo, "foo.md")
--   note:add_alias "Foo Bar"
--   -- TODO: save to another location is weird, it is not move, because obj still has old path.
--   note:save {
--     path = "./tests/fixtures/notes/foo_bar.md",
--     insert_frontmatter = true,
--     update_content = function(a)
--       return a
--     end,
--   }
--   local lines = vim.fn.readfile "./tests/fixtures/notes/foo_bar.md"
--   eq(foo_bar, table.concat(lines, "\n"))
-- end

T["save"] = new_set()

T["save"]["should be able to save a new note"] = function()
  local note = M.new("FOO", {}, {}, "/tmp/" .. util.zettel_id() .. ".md")
  note:save()
  eq(true, note.path:exists())
  vim.fn.delete(note.path.filename)
  eq(false, note.path:exists())
end

T["save"]["should create new files with trailing newline"] = function()
  local note = M.new("FOO", { "foo" }, {}, "/tmp/" .. util.zettel_id() .. ".md")
  note.title = "Foo"
  note:save()

  local file = io.open(tostring(note.path), "rb")
  local content = file:read "*all"
  file:close()

  -- Verify the file ends with a newline character.
  eq("\n", content:sub(-1))

  vim.fn.delete(note.path.filename)
end

T["save"]["should preserve eol status"] = function()
  local temp_path = "/tmp/" .. util.zettel_id() .. ".md"
  util.write_file(temp_path, "# Test\n\nContent here\n")

  local note = M.from_file(temp_path)
  note:save()

  -- Verify the trailing newline is still present.
  local file = io.open(temp_path, "rb")
  file:seek("end", -1)
  eq("\n", file:read(1))
  file:close()

  vim.fn.delete(temp_path)
end

T["save"]["should preserve noeol status"] = function()
  local temp_path = "/tmp/" .. util.zettel_id() .. ".md"
  util.write_file(temp_path, "# Test\n\nContent here")

  local note = M.from_file(temp_path)
  note:save()

  -- Verify the trailing newline is still absent.
  local file = io.open(temp_path, "rb")
  file:seek("end", -1)
  not_eq("\n", file:read(1))
  file:close()

  vim.fn.delete(temp_path)
end

T["save"]["should not error on :checktime when save path contains regex-special characters"] = function()
  -- Regression: the old code passed `save_path.filename` as a string to
  -- `:checktime`, which treats it as a Vim regex pattern. Paths with `[`,
  -- `]`, `*`, etc. (legal in note filenames, e.g. `[[wiki]] title.md`)
  -- would raise E94 even when a buffer was loaded for the exact path.
  local path = "/tmp/" .. util.zettel_id() .. " [draft].md"
  local note = M.new("FOO", {}, {}, path)
  note:save()

  vim.cmd.edit(vim.fn.fnameescape(path))

  note:save() -- must not raise E94

  vim.cmd "bwipeout!"
  vim.fn.delete(path)
end

T["write"] = new_set()

T["write"]["should not add default frontmatter template when frontmatter is disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false

  local note = M.create { id = "Foo", template = Obsidian.opts.note.template }
  note:write()

  local saved_note = M.from_file(note.path)
  eq(false, saved_note.has_frontmatter)
end

T["write"]["should not call frontmatter function when frontmatter is disabled"] = function()
  local calls = 0
  Obsidian.opts.frontmatter.enabled = false
  Obsidian.opts.frontmatter.func = function()
    calls = calls + 1
    return { id = "SHOULD_NOT_BE_WRITTEN" }
  end

  local note = M.create { id = "Foo" }
  note:write()

  eq(0, calls)
  local saved_note = M.from_file(note.path)
  eq(false, saved_note.has_frontmatter)
end

T["write"]["should preserve explicit template frontmatter when frontmatter is disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false
  h.write("---\ncustom: true\n---\nBody", Obsidian.dir / "templates" / "custom.md")

  local note = M.create { id = "Foo", template = "custom.md" }
  note:write()

  local lines = h.read(note.path)
  eq("---", lines[1])
  eq("custom: true", lines[2])
  eq("---", lines[3])
  eq("Body", lines[4])
end

T["add_alias"] = new_set()

T["add_alias"]["should be able to add an alias"] = function()
  local note = from_str(foo, "foo.md")
  eq(#note.aliases, 2)
  note:add_alias "Foo Bar"
  eq(#note.aliases, 3)
end

T["from_lines"] = new_set()

T["from_lines"]["should work from a lines"] = function()
  local note = from_str(foo, "foo.md")
  eq(note.id, "foo")
  eq(note.aliases[1], "foo")
  eq(note.aliases[2], "Foo")
  eq(note:fname(), "foo.md")
  eq(true, note.has_frontmatter)
  eq(#note.tags, 0)
end

local note_with_headers = [[---
id: note_with_a_bunch_of_headers
---

# Header 1

## Sub header 1 A

# Header 2

## Sub header 2 A

## Sub header 3 A]]

--- Strip the `section` references so anchors can be compared with `eq`.
---@param anchor obsidian.note.HeaderAnchor|?
local function anchor_fields(anchor)
  if anchor == nil then
    return nil
  end
  return {
    anchor = anchor.anchor,
    line = anchor.line,
    header = anchor.header,
    level = anchor.level,
    parent = anchor_fields(anchor.parent),
  }
end

T["from_lines"]["should be able to collect anchor links"] = function()
  local note = from_str(note_with_headers, "anchors.md", {
    collect_anchor_links = true,
  })
  eq(note.id, "note_with_a_bunch_of_headers")
  not_eq(note.anchor_links, nil)
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, anchor_fields(note.anchor_links["#header-1"]))
  eq({
    anchor = "#sub-header-1-a",
    line = 7,
    header = "Sub header 1 A",
    level = 2,
    parent = anchor_fields(note.anchor_links["#header-1"]),
  }, anchor_fields(note.anchor_links["#sub-header-1-a"]))
  eq({
    anchor = "#header-2",
    line = 9,
    header = "Header 2",
    level = 1,
  }, anchor_fields(note.anchor_links["#header-2"]))
  eq({
    anchor = "#sub-header-2-a",
    line = 11,
    header = "Sub header 2 A",
    level = 2,
    parent = anchor_fields(note.anchor_links["#header-2"]),
  }, anchor_fields(note.anchor_links["#sub-header-2-a"]))
  eq({
    anchor = "#sub-header-3-a",
    line = 13,
    header = "Sub header 3 A",
    level = 2,
    parent = anchor_fields(note.anchor_links["#header-2"]),
  }, anchor_fields(note.anchor_links["#sub-header-3-a"]))
  eq({
    anchor = "#header-2#sub-header-3-a",
    line = 13,
    header = "Sub header 3 A",
    level = 2,
    parent = anchor_fields(note.anchor_links["#header-2"]),
  }, anchor_fields(note.anchor_links["#header-2#sub-header-3-a"]))
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, anchor_fields(note:resolve_anchor_link "#header-1"))
  eq({
    anchor = "#header-1",
    line = 5,
    header = "Header 1",
    level = 1,
  }, anchor_fields(note:resolve_anchor_link "#Header 1"))
end

T["from_lines"]["should collect sections with full ranges for anchors"] = function()
  local note = from_str(note_with_headers, "anchors.md", {
    collect_anchor_links = true,
  })
  not_eq(nil, note.sections)
  -- preamble + 5 headers
  eq(6, #note.sections)
  eq(nil, note.sections[1].header)

  local h1 = note.anchor_links["#header-1"].section
  -- "# Header 1" (line 5) through "## Sub header 1 A" content (line 7), i.e. until "# Header 2".
  eq({ start_row = 4, start_col = 0, end_row = 7, end_col = 0 }, h1.range)
  eq({ start_row = 4, start_col = 0, end_row = 5, end_col = 0 }, h1.heading_range)

  local h2 = note.anchor_links["#header-2"].section
  -- "# Header 2" (line 9) through the last sub header (line 13).
  eq({ start_row = 8, start_col = 0, end_row = 13, end_col = 0 }, h2.range)
  eq(h2, note.anchor_links["#sub-header-2-a"].section.parent)
end

T["from_lines"]["should resolve anchor locations to full section ranges"] = function()
  local note = from_str(note_with_headers, "anchors.md", {
    collect_anchor_links = true,
  })
  local location = note:_location { anchor = "#header-2" }
  eq({
    start = { line = 8, character = 0 },
    ["end"] = { line = 13, character = 0 },
  }, location.range)
end

T["from_lines"]["should collect setext header anchors"] = function()
  local note = from_str("Title\n=====\n\nBody", "setext.md", {
    collect_anchor_links = true,
  })

  eq({
    anchor = "#title",
    line = 1,
    header = "Title",
    level = 1,
  }, anchor_fields(note.anchor_links["#title"]))
  eq({
    start = { line = 0, character = 0 },
    ["end"] = { line = 4, character = 0 },
  }, note:_location({ anchor = "#title" }).range)
end

local note_with_blocks = [[---
id: note_with_a_bunch_of_blocks
---

This is a block ^1234

And another block ^hello-world]]

T["from_lines"]["should be able to collect blocks"] = function()
  local note = from_str(note_with_blocks, "blocks.md", { collect_blocks = true })
  not_eq(nil, note.blocks)
  eq({
    id = "^1234",
    line = 5,
    block = "This is a block ^1234",
  }, {
    id = note.blocks["^1234"].id,
    line = note.blocks["^1234"].line,
    block = note.blocks["^1234"].block,
  })
  eq({
    id = "^hello-world",
    line = 7,
    block = "And another block ^hello-world",
  }, {
    id = note.blocks["^hello-world"].id,
    line = note.blocks["^hello-world"].line,
    block = note.blocks["^hello-world"].block,
  })
  -- Each block carries the paragraph it lives in as a section.
  eq({ start_row = 4, start_col = 0, end_row = 5, end_col = 0 }, note.blocks["^1234"].section.range)
  eq({ start_row = 6, start_col = 0, end_row = 7, end_col = 0 }, note.blocks["^hello-world"].section.range)
end

T["from_lines"]["should map block ids to the referenced paragraph"] = function()
  local note = from_str("text ^123", "block-inline.md", { collect_blocks = true })
  eq({ start_row = 0, start_col = 0, end_row = 1, end_col = 0 }, note.blocks["^123"].section.range)

  note = from_str("text\ntext2\n^123", "block-multiline.md", { collect_blocks = true })
  eq({ start_row = 0, start_col = 0, end_row = 3, end_col = 0 }, note.blocks["^123"].section.range)

  note = from_str("text\ntext2\n\n^123", "block-standalone.md", { collect_blocks = true })
  eq({ start_row = 0, start_col = 0, end_row = 2, end_col = 0 }, note.blocks["^123"].section.range)
end

T["from_lines"]["should work from a file w/o frontmatter"] = function()
  local note = from_str("# Hey there", "note_without_frontmatter.md")
  eq(note.id, "note_without_frontmatter")
  eq(#note.aliases, 0)
  eq(#note.tags, 0)
  not_eq(note:fname(), nil)
  eq(false, note.has_frontmatter)
end

T["body_lines"] = new_set()

T["body_lines"]["should return full contents when no frontmatter"] = function()
  local note = from_str("# Title\n\nBody line", "no_frontmatter.md", { load_contents = true })
  eq({ "# Title", "", "Body line" }, note:body_lines())
end

T["body_lines"]["should return contents after frontmatter"] = function()
  local note = from_str("---\nid: test\n---\n\nBody line 1\n\nBody line 2", "with_frontmatter.md", {
    load_contents = true,
  })
  eq({ "", "Body line 1", "", "Body line 2" }, note:body_lines())
end

T["merge"] = new_set()

T["merge"]["should merge aliases, tags, and metadata"] = function()
  local base_note = from_str(
    [[---
id: self
aliases:
   - alpha
tags:
   - one
foo: bar
---]],
    "self.md"
  )
  local other_note = from_str(
    [[---
aliases:
   - beta
tags:
   - two
foo: baz
extra:
   - 1
   - 2
---]],
    "other.md"
  )

  base_note:merge(other_note)

  eq(true, base_note:has_alias "beta")
  eq(true, base_note:has_tag "two")
  eq({ "bar", "baz" }, base_note.metadata.foo)
  eq({ 1, 2 }, base_note.metadata.extra)
end

T["merge"]["should do nothing when other has no frontmatter"] = function()
  local base_note = from_str("---\nfoo: bar\n---", "self.md", { load_contents = true })
  local other_note = from_str("Just body", "other.md", { load_contents = true })

  base_note:merge(other_note)

  eq("bar", base_note.metadata.foo)
end

T["merge"]["should merge into note with no frontmatter"] = function()
  local base_note = from_str("Just body content", "self.md", { load_contents = true })
  local other_note = from_str(
    [[---
aliases:
   - beta
tags:
   - two
foo: baz
---]],
    "other.md"
  )

  base_note:merge(other_note)

  eq(true, base_note:has_alias "beta")
  eq(true, base_note:has_tag "two")
  eq("baz", base_note.metadata.foo)
  eq(true, base_note.has_frontmatter)
end

T["from_file"] = new_set()

T["from_file"]["should work from a README"] = function()
  local note = M.from_file "README.md"
  eq(note.id, "README")
  eq(#note.tags, 0)
  eq(note:fname(), "README.md")
  eq(false, note:should_save_frontmatter())
end

T["_is_frontmatter_boundary()"] = function()
  eq(true, M._is_frontmatter_boundary "---")
  eq(true, M._is_frontmatter_boundary "----")
end

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  notes_subdir = "/custom/path/to/zettels",
  note_id_func = function()
    return "hummus"
  end,
}

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
  local temp_template = api.templates_dir() / "zettel"
  vim.fn.writefile({}, tostring(temp_template))

  local spec = assert(M._get_creation_opts { template = "zettel" })

  eq(spec.notes_subdir, zettelConfig.notes_subdir)
  eq(spec.note_id_func, zettelConfig.note_id_func)
end

T["_get_note_creation_opts"]["should fallback to global note_id_func if customization omits it"] = function()
  local partialConfig = {
    notes_subdir = "partials",
  }
  Obsidian.opts.templates.customizations = {
    Partial = partialConfig,
  }
  local temp_template = api.templates_dir() / "Partial"
  vim.fn.writefile({}, tostring(temp_template))
  local spec = assert(M._get_creation_opts { template = "Partial" })
  eq(spec.notes_subdir, "partials")
  eq(spec.note_id_func, Obsidian.opts.note_id_func)
end

T["new_note_path"] = new_set()

T["new_note_path"]['should only append one ".md" at the end of the path'] = function()
  Obsidian.opts.note_path_func = function(spec)
    return (spec.dir / "foo-bar-123"):with_suffix ".md.md.md"
  end

  -- Okay to set `id` and `dir` to default values because `note_path_func` is set
  local path = M._generate_path("", Path:new())
  eq(Path:new() / "foo-bar-123.md", path) -- TODO: ?
end

T["resolve_id_path"] = new_set {
  hooks = {
    pre_case = function()
      Obsidian.opts.note_id_func = function(id)
        if not id then
          id = ""
          for _ = 1, 4 do
            id = id .. string.char(math.random(65, 90))
          end
          return id
        end
        return id
      end
    end,
  },
}

T["resolve_id_path"]["should parse a id that's a partial path and generate new ID"] = function()
  local id, path = M._resolve_id_path {
    id = "notes/Foo",
  }
  eq(id, "Foo")
  eq(Path.new(Obsidian.dir) / "notes" / "Foo.md", path)

  id, path = M._resolve_id_path {
    id = "notes/New Title",
  }
  eq("New Title", id)
  eq(Path.new(Obsidian.dir) / "notes" / "New Title.md", path)
end

T["resolve_id_path"]["should interpret relative directories relative to vault root."] = function()
  local id, path = M._resolve_id_path {
    id = "Foo",
    dir = "new-notes",
  }
  eq(id, "Foo")
  eq(path, Path.new(Obsidian.dir) / "new-notes" / "Foo.md")
end

T["resolve_id_path"]["should ignore boundary whitespace when parsing a title"] = function()
  local id, path = M._resolve_id_path {
    id = "notes/Foo  ",
  }
  eq(id, "Foo")
  eq(tostring(path), tostring(Path.new(Obsidian.dir) / "notes" / "Foo.md"))
end

T["resolve_id_path"]["should keep whitespace within a path when parsing an id"] = function()
  local id, path = M._resolve_id_path {
    id = "notes/Foo Bar.md",
  }
  eq(id, "Foo Bar")
  eq(tostring(path), tostring(Path.new(Obsidian.dir) / "notes" / "Foo Bar.md"))
end

T["resolve_id_path"]["should keep allow decimals in ID"] = function()
  local id, path = M._resolve_id_path {
    id = "johnny.decimal",
    dir = "notes",
  }
  eq(id, "johnny.decimal")
  eq(tostring(Path.new(Obsidian.dir) / "notes" / "johnny.decimal.md"), tostring(path))
end

T["resolve_id_path"]["should generate a new id when the id is just a folder"] = function()
  local id, path = M._resolve_id_path { id = "notes/" }
  eq(#id, 4)
  eq(tostring(path), tostring(Path.new(Obsidian.dir) / "notes" / (id .. ".md")))
end

T["resolve_id_path"]["should respect configured 'note_path_func'"] = function()
  Obsidian.opts.note_path_func = function(spec)
    return (spec.dir / "foo-bar-123"):with_suffix ".md"
  end

  local id, path = M._resolve_id_path { id = "New Note" }
  eq("New Note", id)
  eq(Path.new(Obsidian.dir) / "foo-bar-123.md", path)
end

T["resolve_id_path"]["should ensure result of 'note_path_func' always has '.md' suffix"] = function()
  Obsidian.opts.note_path_func = function(spec)
    return spec.dir / "foo-bar-123"
  end

  local id, path = M._resolve_id_path {
    id = "New Note",
  }
  eq("New Note", id)
  eq(Path.new(Obsidian.dir) / "foo-bar-123.md", path)
end

T["resolve_id_path"]["should ensure result of 'note_path_func' is always an absolute path and within provided directory"] = function()
  Obsidian.opts.note_path_func = function(_)
    return "foo-bar-123.md"
  end

  (Obsidian.dir / "notes"):mkdir { exist_ok = true }

  local id, path = M._resolve_id_path {
    id = "New Note",
    dir = Obsidian.dir / "notes",
  }
  eq("New Note", id)
  eq(Path.new(Obsidian.dir) / "notes" / "foo-bar-123.md", path)
end

T["resolve_id_path"]["should use cwd for non-note buffers when cwd is in vault"] = function()
  local previous_cwd = vim.fn.getcwd()
  local notes_dir = Obsidian.dir / "notes"
  local stale_dir = Obsidian.dir / "stale"
  notes_dir:mkdir { exist_ok = true }
  stale_dir:mkdir { exist_ok = true }

  vim.cmd "enew!"
  Obsidian.buf_dir = stale_dir
  vim.cmd("cd " .. vim.fn.fnameescape(tostring(notes_dir)))

  local id, path = M._resolve_id_path { id = "Foo" }

  vim.cmd("cd " .. vim.fn.fnameescape(previous_cwd))
  eq("Foo", id)
  eq(notes_dir / "Foo.md", path)
end

T["resolve_id_path"]["should prefer current note directory over cwd"] = function()
  local previous_cwd = vim.fn.getcwd()
  local notes_dir = Obsidian.dir / "notes"
  local other_dir = Obsidian.dir / "other"
  notes_dir:mkdir { exist_ok = true }
  other_dir:mkdir { exist_ok = true }

  local current_note = notes_dir / "Current.md"
  vim.fn.writefile({}, tostring(current_note))
  vim.cmd("edit " .. vim.fn.fnameescape(tostring(current_note)))
  vim.cmd("cd " .. vim.fn.fnameescape(tostring(other_dir)))

  local id, path = M._resolve_id_path { id = "Foo" }

  vim.cmd("cd " .. vim.fn.fnameescape(previous_cwd))
  vim.cmd "enew!"
  eq("Foo", id)
  eq(notes_dir / "Foo.md", path)
end

T["resolve_id_path"]["should not use cwd when current buffer is a daily note"] = function()
  local previous_cwd = vim.fn.getcwd()
  Obsidian.opts.daily_notes.folder = "daily"
  local daily_dir = Obsidian.dir / "daily"
  local other_dir = Obsidian.dir / "other"
  daily_dir:mkdir { exist_ok = true }
  other_dir:mkdir { exist_ok = true }

  local current_note = daily_dir / "Today.md"
  vim.fn.writefile({}, tostring(current_note))
  vim.cmd("edit " .. vim.fn.fnameescape(tostring(current_note)))
  vim.cmd("cd " .. vim.fn.fnameescape(tostring(other_dir)))

  local id, path = M._resolve_id_path { id = "Foo" }

  vim.cmd("cd " .. vim.fn.fnameescape(previous_cwd))
  vim.cmd "enew!"
  eq("Foo", id)
  eq(Obsidian.dir / "Foo.md", path)
end

T["format_link"] = new_set()

T["format_link"]["should respect link.style"] = function()
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str(foo, Obsidian.dir / "notes/foo.md")

  Obsidian.opts.link.style = "wiki"
  eq("[[foo]]", note:format_link { label = "foo" })

  Obsidian.opts.link.style = "markdown"
  eq("[foo](foo.md)", note:format_link { label = "foo" })
end

T["format_link"]["wiki should include label only when different from raw basename"] = function()
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str(foo, Obsidian.dir / "notes/foo-bar.md")

  Obsidian.opts.link.style = "wiki"
  Obsidian.opts.link.format = "shortest"

  eq("[[foo-bar]]", note:format_link { label = "foo-bar" })
  eq("[[foo-bar|Foo Bar]]", note:format_link { label = "Foo Bar" })
end

T["format_link"]["should respect custom link formatter callbacks"] = function()
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str(foo, Obsidian.dir / "notes/foo.md")

  Obsidian.opts.link.style = function(opts)
    return "W:" .. tostring(opts.path)
  end
  eq("W:foo.md", note:format_link())
end

T["format_link"]["opts.format should override global link.format"] = function()
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str(foo, Obsidian.dir / "notes/foo.md")

  Obsidian.opts.link.format = "absolute"
  eq("[[foo]]", note:format_link { format = "shortest", label = "foo" })
  eq("[[notes/foo|foo]]", note:format_link { format = "absolute", label = "foo" })
end

T["format_link"]["relative format should fallback to vault root when current note dir is unavailable"] = function()
  Obsidian.opts.link.format = "relative"
  Obsidian.buf_dir = nil

  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str(foo, Obsidian.dir / "notes/foo.md")

  eq("[[notes/foo|foo]]", note:format_link { label = "foo" })
end

T["format_link"]["wiki should respect link.format"] = function()
  -- default to link.style = "shortest"
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str("", Obsidian.dir / "notes/foo.md")
  eq("[[foo]]", note:format_link())
  Obsidian.opts.link.format = "absolute"
  eq("[[notes/foo|foo]]", note:format_link())

  Obsidian.opts.link.format = "relative"

  local subfolder = Obsidian.dir / "notes" / "sub"
  subfolder:mkdir { exist_ok = true }

  Obsidian.buf_dir = subfolder
  eq("[[../foo|foo]]", note:format_link())

  Obsidian.buf_dir = Obsidian.dir / "notes"
  local bar_note = from_str("", Obsidian.dir / "notes/sub/bar.md")
  eq("[[sub/bar|bar]]", bar_note:format_link())
end

T["format_link"]["markdown should respect link.format"] = function()
  -- default to link.style = "shortest"
  Obsidian.opts.link.style = "markdown"
  (Obsidian.dir / "notes"):mkdir { exist_ok = true }
  local note = from_str("", Obsidian.dir / "notes/foo.md")
  eq("[foo](foo.md)", note:format_link())
  Obsidian.opts.link.format = "absolute"
  eq("[foo](notes/foo.md)", note:format_link())

  Obsidian.opts.link.format = "relative"

  local subfolder = Obsidian.dir / "notes" / "sub"
  subfolder:mkdir { exist_ok = true }

  Obsidian.buf_dir = subfolder
  eq("[foo](../foo.md)", note:format_link())

  Obsidian.buf_dir = Obsidian.dir / "notes"
  local bar_note = from_str("", Obsidian.dir / "notes/sub/bar.md")
  eq("[bar](sub/bar.md)", bar_note:format_link())
end

-- T["reference_paths"] = new_set()
--
-- T["reference_paths"]["do four basic paths"] = function()
--   local path = Obsidian.dir / "hi.md"
--   vim.fn.writefile({ "" }, tostring(path))
--   local note = M.from_file(path)
--   eq({ "hi", "hi.md" }, note:get_reference_paths())
--
--   local sub = Obsidian.dir / "sub"
--   path = sub / "hi.md"
--   sub:mkdir()
--   vim.fn.writefile({ "" }, tostring(path))
--   note = M.from_file(path)
--   eq({ "hi", "sub/hi", "sub%2Fhi", "sub%2Fhi.md", "sub/hi.md", "hi.md" }, note:get_reference_paths())
-- end

T["frontmatter_lines"] = new_set()

T["frontmatter_lines"]["respects opts.frontmatter.sort over parsed key order"] = function()
  -- Regression test for #818: when a note already has frontmatter, the parsed
  -- key order was being assigned to the same `order` local, silently
  -- overwriting the user's configured `opts.frontmatter.sort`.
  local prev_sort = Obsidian.opts.frontmatter.sort
  local prev_func = Obsidian.opts.frontmatter.func
  Obsidian.opts.frontmatter.sort = { "id", "aliases", "start", "created", "modified", "tags" }
  Obsidian.opts.frontmatter.func = function(note)
    local out = { tags = note.tags }
    if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
      for k, v in pairs(note.metadata) do
        out[k] = v
      end
    end
    return out
  end

  local note = from_str [[---
tags:
  - foo
created: 2026-05-20
start: morning
---

# n
]]
  local current_lines = { "---", "tags:", "  - foo", "created: 2026-05-20", "start: morning", "---" }
  local lines = note:frontmatter_lines(current_lines)

  local function find(key)
    for i, line in ipairs(lines) do
      if line:match("^" .. key .. ":") then
        return i
      end
    end
    return nil
  end
  local start_i, created_i, tags_i = find "start", find "created", find "tags"
  eq(true, start_i < created_i)
  eq(true, created_i < tags_i)

  Obsidian.opts.frontmatter.sort = prev_sort
  Obsidian.opts.frontmatter.func = prev_func
end

return T
