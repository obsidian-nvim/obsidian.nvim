local M = {}

-- Ran once on the plugin startup
---@param opts obsidian.config.ClientOpts
function M.register_sources(opts)
  local cmp = require "cmp"

  cmp.register_source("obsidian", require("obsidian.completion.sources.nvim_cmp.refs").new())
  cmp.register_source("obsidian_tags", require("obsidian.completion.sources.nvim_cmp.tags").new())
  if opts.completion.create_new then
    cmp.register_source("obsidian_new", require("obsidian.completion.sources.nvim_cmp.new").new())
  end
end

-- Triggered for each opened markdown buffer that's in a workspace and configures nvim_cmp sources for the current buffer.
---@param opts obsidian.config.ClientOpts
function M.inject_sources(opts)
  local cmp = require "cmp"

  local sources = {
    { name = "obsidian" },
    { name = "obsidian_tags" },
  }
  if opts.completion.create_new then
    table.insert(sources, { name = "obsidian_new" })
  end
  for _, source in pairs(cmp.get_config().sources) do
    if source.name ~= "obsidian" and source.name ~= "obsidian_new" and source.name ~= "obsidian_tags" then
      table.insert(sources, source)
    end
  end
  ---@diagnostic disable-next-line: missing-fields
  cmp.setup.buffer { sources = sources }
end

return M
