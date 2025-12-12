local Bookmarks = require "obsidian.bookmarks"

return function()
  local fp = Bookmarks.resolve_bookmark_file()
  if not fp then
    return
  end

  local f = io.open(fp, "r")
  assert(f, "Failed to open bookmarks file")
  local src = f:read "*a"
  f:close()

  local entries = Bookmarks.parse(src)

  Obsidian.picker.pick(entries, {
    prompt_title = "Bookmarks",
  })
end
