---@diagnostic disable: undefined-global
vim.opt.rtp:append(vim.uv.cwd())
vim.opt.rtp:append "deps/mini.doc"

require("mini.doc").setup {}

local submodules = {
  "lua/obsidian/note.lua",
  "lua/obsidian/workspace.lua",
  "lua/obsidian/path.lua",
}

local hooks = vim.deepcopy(MiniDoc.default_hooks)

hooks.write_pre = function(lines)
  -- Remove first two lines with `======` and `------` delimiters to comply
  -- with `:h local-additions` template
  table.remove(lines, 1)
  table.remove(lines, 1)
  return lines
end

MiniDoc.generate(submodules, "doc/obsidian_api.txt", { hooks = hooks })
