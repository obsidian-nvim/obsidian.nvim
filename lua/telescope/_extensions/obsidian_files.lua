---@diagnostic disable: unresolved-require
local api = require "obsidian.api"
local search = require "obsidian.search"

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
      local dir = api.resolve_workspace_dir()
      opts.cwd = tostring(dir)
      opts.vimgrep_arguments = opts.vimgrep_arguments or search.build_grep_cmd(nil, dir)
      return require("telescope.builtin").live_grep(opts)
    end,
  },
}
