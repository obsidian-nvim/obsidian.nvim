local Bookmarks = require "obsidian.bookmarks"

return function()
  local f = Bookmarks.resolve_bookmark_file()
  if not f then
    return
  end

  local entries = Bookmarks.parse(f)

  Obsidian.picker.pick(entries, {
    prompt_title = "Bookmarks",
  })
end
