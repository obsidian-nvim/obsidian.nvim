local obsidian_client = require("obsidian").get_client()

return function(param, _, _)
  require "obsidian.commands.rename"(obsidian_client, { args = param.newName })
end
