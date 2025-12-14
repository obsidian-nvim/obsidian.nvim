local api = require "obsidian.api"

return function(data)
  local query = data.args

  local dir = api.help_wiki_dir()
  if not dir then
    return
  end

  Obsidian.picker.find_notes {
    prompt_title = "Quick Switch",
    dir = dir,
    query = query,
  }
end
