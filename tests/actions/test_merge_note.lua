local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["merge_note copies content and frontmatter before deleting source"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = [[---
aliases:
  - Source alias
tags:
  - from-source
category: source
---
# Source

Source body.
]],
    ["target.md"] = [[---
tags:
  - existing
category: target
---
# Target

Target body.
]],
    ["referrer.md"] = "See [[source]].\n",
  })

  child.cmd("edit " .. vim.fn.fnameescape(files["source.md"]))
  child.api.nvim_buf_set_lines(0, -2, -1, false, { "Edited source body." })

  local prompt = child.lua(([=[
    Obsidian.opts.frontmatter.enabled = false
    local api = require "obsidian.api"
    api.confirm = function(message)
      _G.merge_note_prompt = message
      return "Yes"
    end
    local Note = require "obsidian.note"
    require("obsidian.actions").merge_note(Note.from_file(%q))
    local merged = Note.from_file(%q)
    _G.merged_note = {
      aliases = merged.aliases,
      tags = merged.tags,
      category = merged.metadata.category,
      body = table.concat(merged:body_lines(), "\\n"),
    }
    return _G.merge_note_prompt
  ]=]):format(files["target.md"], files["target.md"]))

  assert(prompt:find("1 backlink(s) will still point to the deleted note.", 1, true))
  eq(nil, vim.uv.fs_stat(files["source.md"]))
  eq({ "Source alias" }, child.lua_get "merged_note.aliases")
  eq({ "existing", "from-source" }, child.lua_get "merged_note.tags")
  eq({ "target", "source" }, child.lua_get "merged_note.category")
  local body = child.lua_get "merged_note.body"
  assert(body:find("Target body.", 1, true))
  assert(body:find("Edited source body.", 1, true))
  assert(body:find("Target body.", 1, true) < body:find("Edited source body.", 1, true))
end

T["merge_note cancellation keeps source and destination"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "Source body.\n",
    ["target.md"] = "Target body.\n",
  })
  child.cmd("edit " .. vim.fn.fnameescape(files["source.md"]))
  child.lua(([=[
    require("obsidian.api").confirm = function()
      return "No"
    end
    require("obsidian.actions").merge_note(require("obsidian.note").from_file(%q))
  ]=]):format(files["target.md"]))

  assert(vim.uv.fs_stat(files["source.md"]))
  eq({ "Target body.", "" }, h.read(files["target.md"]))
end

return T
