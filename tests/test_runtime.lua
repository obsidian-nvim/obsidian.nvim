local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["finds plugin root without relying on the runtime path name"] = function()
  local root = vim.fn.tempname() .. "/combined-plugin"
  local module_dir = root .. "/lua/obsidian"
  vim.fn.mkdir(module_dir, "p")
  local source = assert(vim.api.nvim_get_runtime_file("lua/obsidian/runtime.lua", false)[1], "runtime.lua not on rtp")
  vim.fn.writefile(vim.fn.readfile(source), module_dir .. "/runtime.lua")

  local ok, result = pcall(function()
    local copy = assert(loadfile(module_dir .. "/runtime.lua"))()
    eq(root, copy.get_plugin_dir())
  end)
  vim.fn.delete(vim.fn.fnamemodify(root, ":h"), "rf")
  assert(ok, result)
end

return T
