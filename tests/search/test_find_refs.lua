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

local opts = { sort_by = false }
vim.o.ignorecase = false
local case_sensitive = names(search.find_notes("friendly", opts))
vim.o.ignorecase = true
vim.o.smartcase = true
local cached = {
  alias = names(search.find_notes("friendly", opts)),
  heading = names(search.find_notes("http-api", {
    sort_by = opts.sort_by,
    match = { references = false, headings = true },
  })),
  block = names(search.find_notes("block-id", {
    sort_by = opts.sort_by,
    match = { references = false, blocks = true },
  })),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
  smartcase_alias = names(search.find_notes("FRIENDLY", opts)),
  smartcase_attachments = search.find_attachments("IMAGE", opts),
  case_sensitive = case_sensitive,
}

local ref_opts = {
  include_notes = false,
  include_attachments = true,
  include_unresolved = true,
  include_tags = true,
}
local function simple_refs(refs)
  return vim.tbl_map(function(ref)
    return { kind = ref.kind, text = ref.text, attachment = ref.attachment == true }
  end, refs)
end
cached.refs = simple_refs(search.find_refs("", ref_opts))
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
    sort_by = opts.sort_by,
    match = { references = false, headings = true },
  })),
  block = names(search.find_notes("block-id", {
    sort_by = opts.sort_by,
    match = { references = false, blocks = true },
  })),
  body = names(search.find_notes("body-only", opts)),
  attachments = vim.tbl_map(vim.fs.basename, search.find_attachments("image", opts)),
  smartcase_alias = names(search.find_notes("FRIENDLY", opts)),
  smartcase_attachments = search.find_attachments("IMAGE", opts),
  refs = simple_refs(search.find_refs("", ref_opts)),
}
filesystem.template_refs = search.find_refs("Template", ref_opts)
local ripgrep = require "obsidian.search.ripgrep"
local original_has_ripgrep = ripgrep._has_ripgrep
ripgrep._has_ripgrep = function()
  return false
end
filesystem.refs_without_rg = simple_refs(search.find_refs("", ref_opts))
ripgrep._has_ripgrep = original_has_ripgrep
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
  eq({}, result.cached.case_sensitive)
  eq({}, result.cached.smartcase_alias)
  eq(result.cached.smartcase_alias, result.filesystem.smartcase_alias)
  eq({}, result.cached.smartcase_attachments)
  eq(result.cached.smartcase_attachments, result.filesystem.smartcase_attachments)
  eq({
    { attachment = true, kind = "attachment", text = "Image.PNG" },
    { attachment = false, kind = "unresolved", text = "Missing" },
    { attachment = true, kind = "unresolved", text = "Missing.pdf" },
  }, result.cached.refs)
  eq(result.cached.refs, result.filesystem.refs)
  eq(result.filesystem.refs, result.filesystem.refs_without_rg)
  eq({}, result.cached.template_refs)
  eq({}, result.filesystem.template_refs)
  eq(true, result.cached.respected_disabled_sort)
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
local match_heading = { references = false, headings = true }
local match_block = { references = false, blocks = true }
local cached = {
  heading = #search.find_notes("hidden-heading", { match = match_heading }),
  block = #search.find_notes("hidden-block", { match = match_block }),
}
cache.shutdown()
local filesystem = {
  heading = #search.find_notes("hidden-heading", { match = match_heading }),
  block = #search.find_notes("hidden-block", { match = match_block }),
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

local function note_ref_texts(refs)
  local texts = {}
  for _, ref in ipairs(refs) do
    if ref.kind == "note" then
      texts[#texts + 1] = ref.text
    end
  end
  return texts
end

local cached = {
  notes = stems(search.find_notes("sub/Note", { dir = dir })),
  attachments = basenames(search.find_attachments("sub/images/foo.png", { dir = dir })),
  refs = note_ref_texts(search.find_refs("", { dir = dir })),
}
cache.shutdown()
local filesystem = {
  notes = stems(search.find_notes("sub/Note", { dir = dir })),
  attachments = basenames(search.find_attachments("sub/images/foo.png", { dir = dir })),
  refs = note_ref_texts(search.find_refs("", { dir = dir })),
}
return { cached = cached, filesystem = filesystem }
  ]]

  eq({ "Note" }, result.cached.notes)
  eq({ "foo.png" }, result.cached.attachments)
  eq({ "sub/Note" }, result.cached.refs)
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
local opts = {
  dir = dir,
  include_notes = false,
  include_attachments = true,
  include_unresolved = true,
}

local cached = search.find_refs("", opts)
cache.shutdown()
local filesystem = search.find_refs("", opts)
return { cached = cached, filesystem = filesystem }
  ]]

  eq({}, result.cached)
  eq(result.cached, result.filesystem)
end

return T
