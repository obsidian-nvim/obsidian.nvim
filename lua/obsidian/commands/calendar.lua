local calendar = require "obsidian.calendar"
local initialized

return function(client)
  local opts = client.opts.calendar
  initialized = initialized or calendar.setup(opts)
  vim.cmd(opts.cmd)
end
