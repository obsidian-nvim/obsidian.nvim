local diag = require "obsidian.lsp.diagnostics"

return function(params, dispatchers)
  diag.schedule(params, dispatchers)
end
