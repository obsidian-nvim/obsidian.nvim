local h = dofile "tests/helpers.lua"

local eq = MiniTest.expect.equality
local T, child = h.child_vault()

T["find APIs share structured semantics across cache and filesystem routes"] = function()
  h.child_mock_vault_contents(child, {
    ["Alpha.md"] = [==[
---
id: alpha-id
aliases:
  - Friendly Name
---
# HTTP API
Block target ^block-id
]==],
    ["Body.md"] = "body-only phrase",
    ["Source.md"] = "[[Missing]]\n![[Missing.pdf]]",
    ["templates/Template.md"] = "---\naliases:\n  - Friendly Name\n---\n[[Template Missing]]",
    ["Image.PNG"] = "image",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local search = require "obsidian.search"
local cache = require "obsidian.cache"

local function names(notes)
  local out = {}
  for _, note in ipairs(notes) do
    out[#out + 1] = note.path.stem
  end
  table.sort(out)
  return out
end

local opts = { search = { ignore_case = true, sort = false } }
local cached = {
  alias = names(search.find_notes("friendly", opts)),
  heading = names(search.find_notes("http-api", {
    search = opts.search,
    match = { references = false, headings = true },
  })),
  block = names(search.find_notes("block-id", {
    search = opts.search,
    match = { references = false, blocks = true },
  })),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
}

local refs = search.find_refs("", {
  include_notes = false,
  include_attachments = true,
  include_unresolved = true,
  include_tags = true,
})
cached.refs = vim.tbl_map(function(ref)
  return { kind = ref.kind, text = ref.text, attachment = ref.attachment == true }
end, refs)
cached.template_refs = search.find_refs("Template", {})

local original_sort = table.sort
local sort_called = false
table.sort = function(...)
  sort_called = true
  return original_sort(...)
end
Obsidian.opts.search.sort_by = false
local ok, err = pcall(cache.find_notes, "", {})
table.sort = original_sort
assert(ok, err)
cached.respected_disabled_sort = not sort_called

cache.shutdown()
local filesystem = {
  alias = names(search.find_notes("friendly", opts)),
  heading = names(search.find_notes("http-api", {
    search = opts.search,
    match = { references = false, headings = true },
  })),
  block = names(search.find_notes("block-id", {
    search = opts.search,
    match = { references = false, blocks = true },
  })),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
  refs = search.find_refs("", { include_notes = true }),
}
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ "Alpha" }, result.cached.alias)
  eq(result.cached.alias, result.filesystem.alias)
  eq({ "Alpha" }, result.cached.heading)
  eq(result.cached.heading, result.filesystem.heading)
  eq({ "Alpha" }, result.cached.block)
  eq(result.cached.block, result.filesystem.block)
  eq({}, result.cached.body)
  eq(result.cached.body, result.filesystem.body)
  eq({ "Image.PNG" }, result.cached.attachments)
  eq(result.cached.attachments, result.filesystem.attachments)
  eq({
    { attachment = true, kind = "attachment", text = "Image.PNG" },
    { attachment = false, kind = "unresolved", text = "Missing" },
    { attachment = true, kind = "unresolved", text = "Missing.pdf" },
  }, result.cached.refs)
  eq({}, result.cached.template_refs)
  eq(true, result.cached.respected_disabled_sort)
  eq({}, result.filesystem.refs)
end

return T
