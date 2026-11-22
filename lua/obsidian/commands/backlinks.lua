local navigation = require "obsidian.navigation"

return function()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    navigation.jump_to_locations(locations, { prompt = "Backlinks" })
  end)
end
