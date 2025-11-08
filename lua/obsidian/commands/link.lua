local obsidian = require "obsidian"
local api = obsidian.api

return function(data)
  vim.print(data)
  api.link()
end
