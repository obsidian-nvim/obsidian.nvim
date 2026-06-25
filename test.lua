local note = require("obsidian.search").resolve_note("test")[1]

print(note.path)

note:delete()
