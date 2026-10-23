local obsidian = require "obsidian"

return function()
  obsidian.actions.link(obsidian.api.get_visual_selection())
end
