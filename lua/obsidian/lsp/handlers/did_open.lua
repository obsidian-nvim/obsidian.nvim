local diag = require "obsidian.lsp.diagnostics"

return function(params, dispatchers)
  diag.publish(params, dispatchers)
end
