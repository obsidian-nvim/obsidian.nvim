local Path = require "obsidian.path"
local h = dofile "tests/helpers.lua"
local eq = MiniTest.expect.equality

---@diagnostic disable-next-line: missing-fields
_G.Obsidian = {}

local client_opts = {
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
}

describe("Client:parse_title_id_path()", function()
  it("should parse a title that's a partial path and generate new ID", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo"
      eq("Foo", title)
      eq("foo", id)
      eq(Path:new(Obsidian.dir) / "notes" / "foo.md", path)

      title, id, path = client:parse_title_id_path "notes/New Title"
      eq("New Title", title)
      eq("new-title", id)
      eq(Path:new(Obsidian.dir) / "notes" / "new-title.md", path)
    end, nil, client_opts)
  end)

  it("should interpret relative directories relative to vault root.", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Foo", nil, "new-notes")
      eq(title, "Foo")
      eq(id, "foo")
      eq(path, Path:new(Obsidian.dir) / "new-notes" / "foo.md")
    end, nil, client_opts)
  end)

  it("should parse an ID that's a path", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Foo", "notes/1234-foo")
      eq(title, "Foo")
      eq(id, "1234-foo")
      eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "1234-foo.md"))
    end, nil, client_opts)
  end)

  it("should parse a title that's an exact path", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/foo.md"
      eq(title, "foo")
      eq(id, "foo")
      eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "foo.md"))
    end)
  end)

  it("should ignore boundary whitespace when parsing a title", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo  "
      eq(title, "Foo")
      eq(id, "foo")
      eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "foo.md"))
    end, nil, client_opts)
  end)

  it("should keep whitespace within a path when parsing a title", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo Bar.md"
      eq(title, "Foo Bar")
      eq(id, "Foo Bar")
      eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / "Foo Bar.md"))
    end)
  end, nil, client_opts)

  it("should keep allow decimals in ID", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Title", "johnny.decimal", "notes")
      eq(title, "Title")
      eq(id, "johnny.decimal")
      eq(tostring(Path.new(Obsidian.dir) / "notes" / "johnny.decimal.md"), tostring(path))
    end)
  end)

  it("should generate a new id when the title is just a folder", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/"
      eq(title, nil)
      eq(#id, 4)
      eq(tostring(path), tostring(Path:new(Obsidian.dir) / "notes" / (id .. ".md")))
    end, nil, client_opts)
  end)

  it("should respect configured 'note_path_func'", function()
    h.with_tmp_client(function(client)
      Obsidian.opts.note_path_func = function(spec)
        return (spec.dir / "foo-bar-123"):with_suffix ".md"
      end

      local title, id, path = client:parse_title_id_path "New Note"
      eq("New Note", title)
      eq("new-note", id)
      eq(Path:new(Obsidian.dir) / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)

  it("should ensure result of 'note_path_func' always has '.md' suffix", function()
    h.with_tmp_client(function(client)
      Obsidian.opts.note_path_func = function(spec)
        return spec.dir / "foo-bar-123"
      end

      local title, id, path = client:parse_title_id_path "New Note"
      eq("New Note", title)
      eq("new-note", id)
      eq(Path:new(Obsidian.dir) / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)

  it("should ensure result of 'note_path_func' is always an absolute path and within provided directory", function()
    h.with_tmp_client(function(client)
      Obsidian.opts.note_path_func = function(_)
        return "foo-bar-123.md"
      end

      (Obsidian.dir / "notes"):mkdir { exist_ok = true }

      local title, id, path = client:parse_title_id_path("New Note", nil, Obsidian.dir / "notes")
      eq("New Note", title)
      eq("new-note", id)
      eq(Path:new(Obsidian.dir) / "notes" / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)
end)

describe("Client:_prepare_search_opts()", function()
  it("should prepare search opts properly", function()
    h.with_tmp_client(function(client)
      ---@diagnostic disable-next-line: invisible
      local opts = client:_prepare_search_opts(true, { max_count_per_file = 1 })
      eq(require("obsidian.search").SearchOpts.to_ripgrep_opts(opts), { "--sortr=modified", "-m=1" })
    end)
  end)
end)

describe("Client:create_note()", function()
  it("should create a new note with or without aliases and tags", function()
    h.with_tmp_client(function(client)
      local note = client:create_note { title = "Foo", aliases = { "Bar" }, tags = { "note" } }
      eq(note.title, "Foo")
      eq(note.aliases, { "Bar", "Foo" })
      eq(note.tags, { "note" })
      eq(note.path, Obsidian.dir / "foo.md")
    end, nil, client_opts)
  end)
end)
