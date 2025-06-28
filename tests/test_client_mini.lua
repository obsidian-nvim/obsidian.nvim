local h = dofile "tests/helpers.lua"
local Path = require "obsidian.path"

local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq, has_error = expect.equality, expect.error

local fixtures = vim.fs.joinpath(vim.uv.cwd(), "tests", "fixtures", "notes")

local T = new_set()

T["Client:apply_async_raw"] = function()
  local c = 0
  h.with_tmp_client(function(client)
    client:apply_async_raw(function(path)
      eq(true, vim.endswith(path, ".md"))
      c = c + 1
    end, {
      on_done = function()
        eq(11, c)
      end,
    })
  end, fixtures)
end

T["new_note_path"] = new_set()

T["new_note_path"]['should only append one ".md" at the end of the path'] = function()
  h.with_tmp_client(function(client)
    Obsidian.opts.note_path_func = function(spec)
      return (spec.dir / "foo-bar-123"):with_suffix ".md.md.md"
    end

    -- Okay to set `id` and `dir` to default values because `note_path_func` is set
    local path = client:new_note_path { id = "", dir = Path:new() }
    eq(Path:new() / "foo-bar-123.md", path)
  end)
end

return T
