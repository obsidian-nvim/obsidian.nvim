local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua" }
      child.lua [[M = require"obsidian.api";
Path = require "obsidian.path"
_G.dir = Path.temp { suffix = "-obsidian" }
dir:mkdir { parents = true }
      ]]
    end,
    post_case = function() end,
  },
}

T["find_tags"] = new_set()

T["find_tags"]["should find positions of all tags"] = function()
  child.lua [[
local file = tostring(dir / "tmp.md")
vim.fn.writefile({
  "#hi",
  " #higher",
}, file)

M.find_tags("hi", { dir = tostring(dir) }, function(exit_code, tag_locs)
  res = tag_locs
  vim.fn.delete(tostring(_G.dir), "rf")
end)
  ]]
  vim.uv.sleep(50)
  local tags = child.lua_get "_G.res"

  eq("hi", tags[1].tag)
  eq(0, tags[1].tag_start)
  eq(3, tags[1].tag_end)
  eq("higher", tags[2].tag)
  eq(1, tags[2].tag_start)
  eq(8, tags[2].tag_end)
end

-- T["find_tags"]["should find four cases"] = function()
--   eq(1, #M.find_tags "#camelCase")
--   eq(1, #M.find_tags "#PascalCase")
--   eq(1, #M.find_tags "#snake_case")
--   eq(1, #M.find_tags "#kebab-case")
-- end
--
return T
