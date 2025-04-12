return function(obsidian_client, param, _, _)
  require "obsidian.commands.rename"(obsidian_client, { args = param.newName })
end
