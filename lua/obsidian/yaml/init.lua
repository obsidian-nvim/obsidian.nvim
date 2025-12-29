local M = {}

local dump = require "obsidian.yaml.dump"
M.dumps_lines = dump.dumps_lines
M.dumps = dump.dumps

local function has_treesitter_parser(name)
  local res, _ = pcall(vim.treesitter.language.inspect, name)
  return res
end

if vim.fn.executable "yq" == 1 then
  M.loads = require("obsidian.yaml.yq").loads
elseif has_treesitter_parser "yaml" then
  M.loads = require("obsidian.yaml.treesitter").loads
else
  M.loads = require("obsidian.yaml.lua").loads
end

return M
