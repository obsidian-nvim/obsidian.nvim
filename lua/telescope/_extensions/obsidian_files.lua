---@diagnostic disable: unresolved-require
local api = require "obsidian.api"

---@diagnostic disable-next-line: undefined-field
return require("telescope").register_extension {
  exports = {
    obsidian_files = function(opts)
      opts = opts or {}
      opts.cwd = tostring(api.resolve_workspace_dir())
      return require("telescope.builtin").find_files(opts)
    end,
    obsidian_grep = function(opts)
      opts = opts or {}
      opts.cwd = tostring(api.resolve_workspace_dir())
      return require("telescope.builtin").live_grep(opts)
    end,
  },
}
