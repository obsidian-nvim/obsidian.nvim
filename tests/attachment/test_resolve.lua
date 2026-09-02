local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function find(term, opts)
  return h.child_await(
    child,
    ([[
      require("obsidian.attachment")._find_async(%s, %s, function(matches)
        done(matches)
      end)
    ]]):format(vim.inspect(term), vim.inspect(opts)),
    { desc = "attachment search" }
  )
end

local function resolve(reference, opts)
  return h.child_await(
    child,
    ([[
      require("obsidian.attachment")._resolve_async(%s, %s, function(path, err, candidates)
        done { path = path, err = err, candidates = candidates }
      end)
    ]]):format(vim.inspect(reference), vim.inspect(opts)),
    { desc = "attachment resolution" }
  )
end

local function delete(reference, opts)
  return h.child_await(
    child,
    ([[
      require("obsidian.attachment").delete(%s, %s, function(err, path)
        done { err = err, path = path }
      end)
    ]]):format(vim.inspect(reference), vim.inspect(opts)),
    { desc = "attachment deletion" }
  )
end

local function rename(reference, new_name, opts)
  return h.child_await(
    child,
    ([[
      require("obsidian.attachment").rename(%s, %s, %s, function(err, edit, meta)
        done { err = err, edit = edit, meta = meta }
      end)
    ]]):format(vim.inspect(reference), vim.inspect(new_name), vim.inspect(opts)),
    { desc = "attachment rename" }
  )
end

T["destination_path does not require an existing file"] = function()
  local expected = tostring(child.Obsidian.dir / "attachments" / "missing.png")
  local destination = child.lua [[return require("obsidian.attachment").destination_path("missing.png")]]
  local compatibility = child.lua [[return require("obsidian.attachment").resolve_attachment_path("missing.png")]]

  eq(expected, destination)
  eq(expected, compatibility)
end

T["finds attachments across the vault"] = function()
  local assets = child.Obsidian.dir / "assets"
  assets:mkdir()
  h.write("image", assets / "Photo.PNG")
  h.write("note", assets / "photo.md")

  local matches = find "pho"

  eq(1, #matches)
  eq("Photo.PNG", matches[1].basename)
  eq("assets/Photo.PNG", matches[1].rel_path)
end

T["prefers an existing configured destination for basenames"] = function()
  local configured_dir = child.Obsidian.dir / "attachments"
  local other_dir = child.Obsidian.dir / "assets"
  configured_dir:mkdir()
  other_dir:mkdir()
  local configured = configured_dir / "same.png"
  h.write("configured", configured)
  h.write("other", other_dir / "same.png")

  local result = resolve "same.png"

  eq(tostring(configured), result.path)
  eq(nil, result.err)
end

T["falls back to a unique vault basename"] = function()
  local assets = child.Obsidian.dir / "assets"
  assets:mkdir()
  local expected = assets / "outside.png"
  h.write("image", expected)

  local result = resolve "outside.png"

  eq(tostring(expected), result.path)
  eq(nil, result.err)
end

T["reports ambiguous basename matches"] = function()
  local first_dir = child.Obsidian.dir / "a"
  local second_dir = child.Obsidian.dir / "b"
  first_dir:mkdir()
  second_dir:mkdir()
  h.write("first", first_dir / "same.png")
  h.write("second", second_dir / "same.png")

  local result = resolve "same.png"

  eq(nil, result.path)
  eq("Ambiguous attachment reference 'same.png'", result.err)
  eq(2, #result.candidates)
end

T["resolves note-relative and vault-relative paths"] = function()
  local note_dir = child.Obsidian.dir / "notes"
  local local_assets = note_dir / "assets"
  local vault_assets = child.Obsidian.dir / "shared"
  local_assets:mkdir { parents = true }
  vault_assets:mkdir()
  local note_path = note_dir / "note.md"
  local local_path = local_assets / "local.png"
  local vault_path = vault_assets / "vault.png"
  h.write("image", local_path)
  h.write("image", vault_path)

  local resolved_local = resolve("assets/local.png", { filename = tostring(note_path) })
  local resolved_vault = resolve("shared/vault.png", { filename = tostring(note_path) })

  eq(tostring(local_path), resolved_local.path)
  eq(tostring(vault_path), resolved_vault.path)
end

T["delete resolves a unique vault attachment"] = function()
  local assets = child.Obsidian.dir / "assets"
  assets:mkdir()
  local path = assets / "delete.png"
  h.write("image", path)

  local result = delete "delete.png"

  eq(nil, result.err)
  eq(tostring(path), result.path)
  eq(nil, vim.uv.fs_stat(tostring(path)))
end

T["delete refuses an ambiguous attachment"] = function()
  local first_dir = child.Obsidian.dir / "a"
  local second_dir = child.Obsidian.dir / "b"
  first_dir:mkdir()
  second_dir:mkdir()
  local first = first_dir / "keep.png"
  local second = second_dir / "keep.png"
  h.write("first", first)
  h.write("second", second)
  child.lua [[require("obsidian.log").err = function() end]]

  local result = delete "keep.png"

  eq("Ambiguous attachment reference 'keep.png'", result.err)
  eq(nil, result.path)
  eq(true, first:exists())
  eq(true, second:exists())
end

T["rename updates wiki, Markdown, absolute, and relative references"] = function()
  local assets = child.Obsidian.dir / "assets"
  local notes = child.Obsidian.dir / "notes"
  assets:mkdir()
  notes:mkdir()
  local old_path = assets / "old image.png"
  local new_path = assets / "new image.png"
  local root_note = child.Obsidian.dir / "root.md"
  local nested_note = notes / "nested.md"
  h.write("image", old_path)
  h.write("![[assets/old image.png]]\n![old image.png](assets/old%20image.png)", root_note)
  h.write("![](../assets/old%20image.png)", nested_note)

  local result = rename("assets/old image.png", "new image", { filename = tostring(root_note) })

  eq(nil, result.err)
  eq(tostring(old_path), result.meta.old_path)
  eq(tostring(new_path), result.meta.new_path)
  eq(4, result.meta.count)
  eq(false, old_path:exists())
  eq(true, new_path:exists())
  eq({
    "---",
    "id: root",
    "aliases: []",
    "tags: []",
    "---",
    "![[assets/new image.png]]",
    "![new image.png](assets/new%20image.png)",
  }, h.read(root_note))
  eq({ "---", "id: nested", "aliases: []", "tags: []", "---", "![](../assets/new%20image.png)" }, h.read(nested_note))
end

return T
