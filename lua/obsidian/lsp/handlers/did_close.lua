local diag = require "obsidian.lsp.diagnostics"

return function(params, dispatchers)
  diag.clear(params, dispatchers)
end
