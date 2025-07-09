local h = dofile "tests/helpers.lua"
local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

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

return T
