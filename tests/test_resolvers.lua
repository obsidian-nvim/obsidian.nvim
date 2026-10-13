local Note = require "obsidian.note"
local docs = require "obsidian.completion.docs"
local resolvers = require "obsidian.resolvers"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

--- Build an in-memory note whose contents were not parsed (like cache-built
--- notes with lazily loaded contents).
---@param lines string[]
---@return obsidian.Note
local function raw_note(lines)
  local note = Note.new("foo", {}, {}, "/tmp/vault/foo.md")
  note.contents = lines
  return note
end

T["default_note_preview"] = new_set()

T["default_note_preview"]["resolves the title from frontmatter metadata"] = function()
  local note = raw_note { "---", "tags: []", "---", "# H1 Heading" }
  note.metadata = { title = "Metadata Title" }
  local out = resolvers.default_note_preview { scope = "lsp.completion", note = note }
  eq(true, out:find("**title:** Metadata Title", 1, true) ~= nil)
end

T["default_note_preview"]["skips frontmatter when contents were not parsed"] = function()
  local note = raw_note { "---", "# a yaml comment", "title: x", "---", "", "# Real Title" }
  note.metadata = { title = "x" }
  -- The metadata title wins outright.
  local out = resolvers.default_note_preview { scope = "lsp.completion", note = note }
  eq(true, out:find("**title:** x", 1, true) ~= nil)

  -- Without metadata, the yaml comment must not be picked up as the H1.
  note.metadata = {}
  out = resolvers.default_note_preview { scope = "lsp.completion", note = note }
  eq(true, out:find("**title:** Real Title", 1, true) ~= nil)
end

T["default_note_preview"]["ignores H1s inside code fences and comments"] = function()
  local note = raw_note {
    "```markdown",
    "# Fenced Heading",
    "```",
    "%%",
    "# Commented Heading",
    "%%",
    "# Real Heading",
  }
  local out = resolvers.default_note_preview { scope = "lsp.completion", note = note }
  eq(true, out:find("**title:** Real Heading", 1, true) ~= nil)
  eq(nil, out:find("Fenced Heading", 1, true))
  eq(nil, out:find("Commented Heading", 1, true))
end

T["resolve_item"] = new_set()

T["resolve_item"]["passes items without data through unchanged"] = function()
  local item = { label = "[[foo]]" }
  local result
  docs.resolve_item(item, function(resolved)
    result = resolved
  end)
  eq(item, result)
  eq(nil, result.documentation)
end

T["resolve_item"]["passes items with an unknown key through unchanged"] = function()
  local item = { label = "[[foo]]", data = { obsidian_note_preview = 424242 } }
  local result
  docs.resolve_item(item, function(resolved)
    result = resolved
  end)
  eq(item, result)
  eq(nil, result.documentation)
end

T["resolve_item"]["passes items with non-table data through unchanged"] = function()
  local item = { label = "[[foo]]", data = 42 }
  local result
  docs.resolve_item(item, function(resolved)
    result = resolved
  end)
  eq(item, result)
  eq(nil, result.documentation)
end

return T
