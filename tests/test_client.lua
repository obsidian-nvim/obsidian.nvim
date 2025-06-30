local Path = require "obsidian.path"
local h = dofile "tests/helpers.lua"

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

describe("Client:new_note_path()", function()
  it('should only append one ".md" at the end of the path', function()
    h.with_tmp_client(function(client)
      client.opts.note_path_func = function(spec)
        return (spec.dir / "foo-bar-123"):with_suffix ".md.md.md"
      end

      -- Okay to set `id` and `dir` to default values because `note_path_func` is set
      local path = client:new_note_path { id = "", dir = Path:new() }
      MiniTest.expect.equality(Path:new() / "foo-bar-123.md", path)
    end)
  end)
end)

describe("Client:parse_title_id_path()", function()
  it("should parse a title that's a partial path and generate new ID", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo"
      MiniTest.expect.equality("Foo", title)
      MiniTest.expect.equality("foo", id)
      MiniTest.expect.equality(Path:new(client.dir) / "notes" / "foo.md", path)

      title, id, path = client:parse_title_id_path "notes/New Title"
      MiniTest.expect.equality("New Title", title)
      MiniTest.expect.equality("new-title", id)
      MiniTest.expect.equality(Path:new(client.dir) / "notes" / "new-title.md", path)
    end, nil, client_opts)
  end)

  it("should interpret relative directories relative to vault root.", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Foo", nil, "new-notes")
      MiniTest.expect.equality(title, "Foo")
      MiniTest.expect.equality(id, "foo")
      MiniTest.expect.equality(path, Path:new(client.dir) / "new-notes" / "foo.md")
    end, nil, client_opts)
  end)

  it("should parse an ID that's a path", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Foo", "notes/1234-foo")
      MiniTest.expect.equality(title, "Foo")
      MiniTest.expect.equality(id, "1234-foo")
      MiniTest.expect.equality(tostring(path), tostring(Path:new(client.dir) / "notes" / "1234-foo.md"))
    end, nil, client_opts)
  end)

  it("should parse a title that's an exact path", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/foo.md"
      MiniTest.expect.equality(title, "foo")
      MiniTest.expect.equality(id, "foo")
      MiniTest.expect.equality(tostring(path), tostring(Path:new(client.dir) / "notes" / "foo.md"))
    end)
  end)

  it("should ignore boundary whitespace when parsing a title", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo  "
      MiniTest.expect.equality(title, "Foo")
      MiniTest.expect.equality(id, "foo")
      MiniTest.expect.equality(tostring(path), tostring(Path:new(client.dir) / "notes" / "foo.md"))
    end, nil, client_opts)
  end)

  it("should keep whitespace within a path when parsing a title", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/Foo Bar.md"
      MiniTest.expect.equality(title, "Foo Bar")
      MiniTest.expect.equality(id, "Foo Bar")
      MiniTest.expect.equality(tostring(path), tostring(Path:new(client.dir) / "notes" / "Foo Bar.md"))
    end)
  end, nil, client_opts)

  it("should keep allow decimals in ID", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path("Title", "johnny.decimal", "notes")
      MiniTest.expect.equality(title, "Title")
      MiniTest.expect.equality(id, "johnny.decimal")
      MiniTest.expect.equality(tostring(Path.new(client.dir) / "notes" / "johnny.decimal.md"), tostring(path))
    end)
  end)

  it("should generate a new id when the title is just a folder", function()
    h.with_tmp_client(function(client)
      local title, id, path = client:parse_title_id_path "notes/"
      MiniTest.expect.equality(title, nil)
      MiniTest.expect.equality(#id, 4)
      MiniTest.expect.equality(tostring(path), tostring(Path:new(client.dir) / "notes" / (id .. ".md")))
    end, nil, client_opts)
  end)

  it("should respect configured 'note_path_func'", function()
    h.with_tmp_client(function(client)
      client.opts.note_path_func = function(spec)
        return (spec.dir / "foo-bar-123"):with_suffix ".md"
      end

      local title, id, path = client:parse_title_id_path "New Note"
      MiniTest.expect.equality("New Note", title)
      MiniTest.expect.equality("new-note", id)
      MiniTest.expect.equality(Path:new(client.dir) / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)

  it("should ensure result of 'note_path_func' always has '.md' suffix", function()
    h.with_tmp_client(function(client)
      client.opts.note_path_func = function(spec)
        return spec.dir / "foo-bar-123"
      end

      local title, id, path = client:parse_title_id_path "New Note"
      MiniTest.expect.equality("New Note", title)
      MiniTest.expect.equality("new-note", id)
      MiniTest.expect.equality(Path:new(client.dir) / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)

  it("should ensure result of 'note_path_func' is always an absolute path and within provided directory", function()
    h.with_tmp_client(function(client)
      client.opts.note_path_func = function(_)
        return "foo-bar-123.md"
      end

      (client.dir / "notes"):mkdir { exist_ok = true }

      local title, id, path = client:parse_title_id_path("New Note", nil, client.dir / "notes")
      MiniTest.expect.equality("New Note", title)
      MiniTest.expect.equality("new-note", id)
      MiniTest.expect.equality(Path:new(client.dir) / "notes" / "foo-bar-123.md", path)
    end, nil, client_opts)
  end)
end)

describe("Client:_prepare_search_opts()", function()
  it("should prepare search opts properly", function()
    h.with_tmp_client(function(client)
      ---@diagnostic disable-next-line: invisible
      local opts = client:_prepare_search_opts(true, { max_count_per_file = 1 })
      MiniTest.expect.equality(
        require("obsidian.search").SearchOpts.to_ripgrep_opts(opts),
        { "--sortr=modified", "-m=1" }
      )
    end)
  end)
end)

describe("Client:vault_relative_path()", function()
  it("should resolve relative paths", function()
    h.with_tmp_client(function(client)
      MiniTest.expect.equality(client:vault_relative_path "foo.md", Path.new "foo.md")
      MiniTest.expect.equality(client:vault_relative_path(client.dir / "foo.md"), Path.new "foo.md")
    end)
  end)

  it("should error when strict=true and the relative path can't be resolved", function()
    h.with_tmp_client(function(client)
      MiniTest.expect.error(function()
        client:vault_relative_path("/Users/petew/foo.md", { strict = true })
      end)
    end)
  end)

  it("should not error when strict=false and the relative path can't be resolved", function()
    h.with_tmp_client(function(client)
      MiniTest.expect.equality(nil, client:vault_relative_path "/Users/petew/foo.md")
    end)
  end)
end)
