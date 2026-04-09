local M = {}

local dump = require "obsidian.yaml.dump"
M.dumps_lines = dump.dumps_lines
M.dumps = dump.dumps
M.loads = require("obsidian.yaml.parser").loads

return M
