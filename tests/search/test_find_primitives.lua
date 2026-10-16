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
    ["templates/Template-image.png"] = "template image",
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

local function heading_matches(query)
  return vim.tbl_map(function(match)
    return {
      note = match.note.path.stem,
      header = match.heading.header,
      anchor = match.heading.anchor,
      line = match.heading.line,
    }
  end, search.find_headings(query, { sort_by = false }))
end

local function block_matches(query)
  return vim.tbl_map(function(match)
    return {
      note = match.note.path.stem,
      section = match.section ~= nil,
      blocks = vim.tbl_map(function(block) return block.id end, match.blocks),
    }
  end, search.find_blocks(query, { sort_by = false }))
end

local opts = { sort_by = false }
vim.o.ignorecase = false
local case_sensitive = names(search.find_notes("friendly", opts))
vim.o.ignorecase = true
vim.o.smartcase = true
local cached = {
  alias = names(search.find_notes("friendly", opts)),
  heading_matches = heading_matches("http-api"),
  block_matches = block_matches("block-id"),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
  smartcase_alias = names(search.find_notes("FRIENDLY", opts)),
  smartcase_attachments = search.find_attachments("IMAGE", opts),
  case_sensitive = case_sensitive,
}

local function primitive_results(term)
  local _, missing_notes = search.find_notes(term, { include_unresolved = true })
  local attachments, missing_attachments = search.find_attachments(term, { include_unresolved = true })
  return {
    attachments = vim.tbl_map(vim.fs.basename, attachments),
    missing_notes = vim.tbl_map(function(item) return item.text end, missing_notes),
    missing_attachments = vim.tbl_map(function(item) return item.text end, missing_attachments),
  }
end

cached.primitives = primitive_results("")
cached.template_primitives = primitive_results("Template")

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
  heading_matches = heading_matches("http-api"),
  block_matches = block_matches("block-id"),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
  smartcase_alias = names(search.find_notes("FRIENDLY", opts)),
  smartcase_attachments = search.find_attachments("IMAGE", opts),
  primitives = primitive_results(""),
}
filesystem.template_primitives = primitive_results("Template")
local ripgrep = require "obsidian.search.ripgrep"
local original_has_ripgrep = ripgrep._has_ripgrep
ripgrep._has_ripgrep = function()
  return false
end
filesystem.primitives_without_rg = primitive_results("")
ripgrep._has_ripgrep = original_has_ripgrep
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ "Alpha" }, result.cached.alias)
  eq(result.cached.alias, result.filesystem.alias)
  eq({ { note = "Alpha", header = "HTTP API", anchor = "#http-api", line = 6 } }, result.cached.heading_matches)
  eq(result.cached.heading_matches, result.filesystem.heading_matches)
  eq({ { note = "Alpha", section = true, blocks = { "^block-id" } } }, result.cached.block_matches)
  eq(result.cached.block_matches, result.filesystem.block_matches)
  eq({}, result.cached.body)
  eq(result.cached.body, result.filesystem.body)
  eq({ "Image.PNG" }, result.cached.attachments)
  eq(result.cached.attachments, result.filesystem.attachments)
  eq({}, result.cached.case_sensitive)
  eq({}, result.cached.smartcase_alias)
  eq(result.cached.smartcase_alias, result.filesystem.smartcase_alias)
  eq({}, result.cached.smartcase_attachments)
  eq(result.cached.smartcase_attachments, result.filesystem.smartcase_attachments)
  eq({
    attachments = { "Image.PNG" },
    missing_notes = { "Missing" },
    missing_attachments = { "Missing.pdf" },
  }, result.cached.primitives)
  eq(result.cached.primitives, result.filesystem.primitives)
  eq(result.filesystem.primitives, result.filesystem.primitives_without_rg)
  eq({ attachments = {}, missing_notes = {}, missing_attachments = {} }, result.cached.template_primitives)
  eq(result.cached.template_primitives, result.filesystem.template_primitives)
  eq(true, result.cached.respected_disabled_sort)
end

T["cached structured searches do not read note files"] = function()
  h.child_mock_vault_contents(child, {
    ["Alpha.md"] = "# HTTP API\nBlock target ^block-id",
  })
  h.child_setup_cache(child)

  local result = child.lua [==[
local search = require "obsidian.search"
local Note = require "obsidian.note"
local original_from_file = Note.from_file
Note.from_file = function()
  error "cached search read a note file"
end

local ok, value = pcall(function()
  local headings = search.find_headings("http-api")
  local blocks = search.find_blocks("block-id")
  local note = search.find_notes("Alpha")[1]
  return {
    heading = headings[1] and headings[1].note:resolve_anchor_link "#http-api" and headings[1].note.path.stem,
    block = blocks[1] and blocks[1].note.path.stem,
    lazy_heading = note and note:resolve_anchor_link "#http-api" and note.path.stem,
    lazy_block = note and note:resolve_block "block-id" and note.path.stem,
  }
end)

Note.from_file = original_from_file
assert(ok, value)
return value
  ]==]

  eq({ heading = "Alpha", block = "Alpha", lazy_heading = "Alpha", lazy_block = "Alpha" }, result)
end

T["resolve_note remains case insensitive when ignorecase is disabled"] = function()
  h.child_mock_vault_contents(child, {
    ["Foo.md"] = "---\naliases:\n  - Friendly Name\n---\n# Foo",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local search = require "obsidian.search"
local cache = require "obsidian.cache"

local function names(notes)
  return vim.tbl_map(function(note)
    return note.path.stem
  end, notes)
end

vim.o.ignorecase = false
local cached = {
  filename = names(search.resolve_note "foo"),
  alias = names(search.resolve_note "friendly name"),
}
cache.shutdown()
local filesystem = {
  filename = names(search.resolve_note "foo"),
  alias = names(search.resolve_note "friendly name"),
}
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ "Foo" }, result.cached.filename)
  eq({ "Foo" }, result.cached.alias)
  eq(result.cached, result.filesystem)
end

T["cached heading and block matches respect max_lines"] = function()
  h.child_mock_vault_contents(child, {
    ["Limited.md"] = "intro\n# Hidden Heading\nblock text ^hidden-block",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local search = require "obsidian.search"
local cache = require "obsidian.cache"

Obsidian.opts.search.max_lines = 1
local cached = {
  heading = #search.find_headings("hidden-heading"),
  block = #search.find_blocks("hidden-block"),
}
cache.shutdown()
local filesystem = {
  heading = #search.find_headings("hidden-heading"),
  block = #search.find_blocks("hidden-block"),
}
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ heading = 0, block = 0 }, result.cached)
  eq(result.cached, result.filesystem)
end

T["subdirectory searches match vault-relative paths across backends"] = function()
  h.child_mock_vault_contents(child, {
    ["sub/Note.md"] = "# Note",
    ["sub/images/foo.png"] = "image",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local search = require "obsidian.search"
local cache = require "obsidian.cache"
local dir = Obsidian.dir / "sub"

local function stems(notes)
  return vim.tbl_map(function(note)
    return note.path.stem
  end, notes)
end

local function basenames(paths)
  return vim.tbl_map(vim.fs.basename, paths)
end

local cached = {
  notes = stems(search.find_notes("sub/Note", { dir = dir })),
  attachments = basenames(search.find_attachments("sub/images/foo.png", { dir = dir })),
}
cache.shutdown()
local filesystem = {
  notes = stems(search.find_notes("sub/Note", { dir = dir })),
  attachments = basenames(search.find_attachments("sub/images/foo.png", { dir = dir })),
}
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ "Note" }, result.cached.notes)
  eq({ "foo.png" }, result.cached.attachments)
  eq(result.cached, result.filesystem)
end

T["subdirectory unresolved-link searches resolve targets from the whole workspace"] = function()
  h.child_mock_vault_contents(child, {
    ["Target.md"] = "# Target",
    ["Existing.pdf"] = "attachment",
    ["sub/Source.md"] = "[[Target]]\n![[Existing.pdf]]",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local search = require "obsidian.search"
local cache = require "obsidian.cache"
local dir = Obsidian.dir / "sub"
local opts = { dir = dir, include_unresolved = true }

local _, cached_notes = search.find_notes("", opts)
local _, cached_attachments = search.find_attachments("", opts)
cache.shutdown()
local _, filesystem_notes = search.find_notes("", opts)
local _, filesystem_attachments = search.find_attachments("", opts)
local cached = { notes = #cached_notes, attachments = #cached_attachments }
local filesystem = { notes = #filesystem_notes, attachments = #filesystem_attachments }
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ notes = 0, attachments = 0 }, result.cached)
  eq(result.cached, result.filesystem)
end

return T
