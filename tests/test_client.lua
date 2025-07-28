local h = dofile "tests/helpers.lua"
local eq = MiniTest.expect.equality

---@diagnostic disable-next-line: missing-fields
_G.Obsidian = {}

describe("Client:_prepare_search_opts()", function()
  it("should prepare search opts properly", function()
    h.with_tmp_client(function(client)
      ---@diagnostic disable-next-line: invisible
      local opts = client:_prepare_search_opts(true, { max_count_per_file = 1 })
      eq(require("obsidian.search").SearchOpts.to_ripgrep_opts(opts), { "--sortr=modified", "-m=1" })
    end)
  end)
end)
