local api = require "obsidian.api"
local Note = require "obsidian.note"

local dir = api.resolve_workspace_dir()

local function add(path)
  local note = Note.from_file(path)
  note:add_field("listened", 1)
  note:update_frontmatter()
end

for path in api.dir(dir / "Media DB/music") do
  add(path)
end
