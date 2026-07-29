local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local fs = require "obsidian.fs"
local search = require "obsidian.search"

local T = h.temp_vault

T["ignore gitignore"] = function()
  local gitignore = {
    "ignore/",
    "c.md",
  }
  local dir = Obsidian.dir

  -- TODO: helper.mock_vault_contents
  local ignore_dir = dir / "ignore"
  local a = tostring(dir / "a.md")
  local b = tostring(ignore_dir / "b.md")
  local c = tostring(dir / "c.md")
  local ignore_file = tostring(dir / ".gitignore")
  ignore_dir:mkdir()
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)
  vim.fn.writefile({}, c)
  vim.fn.writefile(gitignore, ignore_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end
  eq(#result, 1)
  eq(result[1], tostring(a))
end

T["ignore dot files"] = function()
  local dir = Obsidian.dir

  local a = tostring(dir / "a.md")
  local b = tostring(dir / ".b.md")
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end
  eq(#result, 1)
  eq(result[1], tostring(a))
end

T["find_files applies nested gitignore rules and negations"] = function()
  local dir = Obsidian.dir
  local nested = dir / "nested"
  nested:mkdir()

  local ignored = tostring(nested / "ignored.md")
  local local_ignored = tostring(nested / "local.md")
  local kept = tostring(nested / "keep.md")
  vim.fn.writefile({ "nested/*.md" }, tostring(dir / ".gitignore"))
  vim.fn.writefile({ "!keep.md", "local.md" }, tostring(nested / ".gitignore"))
  vim.fn.writefile({}, ignored)
  vim.fn.writefile({}, local_ignored)
  vim.fn.writefile({}, kept)

  eq(fs.find_files(dir), { kept })
end

T["find_files supports hidden files, predicates, pruning, and stable sorting"] = function()
  local dir = Obsidian.dir
  local nested = dir / "nested"
  local pruned = dir / "pruned"
  nested:mkdir()
  pruned:mkdir()

  local a = tostring(dir / "a.md")
  local b = tostring(nested / "b.md")
  local hidden = tostring(dir / ".hidden.md")
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)
  vim.fn.writefile({}, hidden)
  vim.fn.writefile({}, tostring(dir / "other.txt"))
  vim.fn.writefile({}, tostring(pruned / "ignored.md"))

  local opts = {
    hidden = true,
    prune = function(path)
      return path == tostring(pruned)
    end,
    predicate = function(path)
      return vim.endswith(path, ".md")
    end,
  }
  eq(fs.find_files(dir, opts), { hidden, a, b })
end

T["walk can enumerate directories with a depth limit"] = function()
  local dir = Obsidian.dir
  local one = dir / "one"
  local two = one / "two"
  one:mkdir()
  two:mkdir()

  local result = {}
  for path, kind in fs.walk(dir, { type = "directory", depth = 1 }) do
    eq(kind, "directory")
    result[#result + 1] = path
  end

  eq(vim.tbl_contains(result, tostring(one)), true)
  eq(vim.tbl_contains(result, tostring(two)), false)
end

T["find_async matches literal filenames without ripgrep"] = function()
  local dir = Obsidian.dir
  local markdown = tostring(dir / "literal-{query}.md")
  local text = tostring(dir / "literal-{query}.txt")
  vim.fn.writefile({}, markdown)
  vim.fn.writefile({}, text)

  local result = {}
  local exit_code
  search.find_async(dir, "{query}", {}, function(path)
    result[#result + 1] = path
  end, function(code)
    exit_code = code
  end)

  vim.wait(1000, function()
    return exit_code ~= nil
  end)
  eq(result, { markdown })
  eq(exit_code, 0)
end

T["find_files_async yields before returning results"] = function()
  local dir = Obsidian.dir
  local a = tostring(dir / "a.md")
  local b = tostring(dir / "b.md")
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)

  local result
  fs.find_files_async(dir, { batch_size = 1 }, function(paths)
    result = paths
  end)

  eq(result, nil)
  vim.wait(1000, function()
    return result ~= nil
  end)
  eq(result, { a, b })
end

T["path sorting does not stat every result"] = function()
  local dir = Obsidian.dir
  vim.fn.writefile({}, tostring(dir / "a.md"))
  vim.fn.writefile({}, tostring(dir / "b.md"))

  local original_fs_stat = vim.uv.fs_stat
  local result_stats = 0
  vim.uv.fs_stat = function(path, ...)
    if vim.fs.basename(path) ~= ".gitignore" then
      result_stats = result_stats + 1
    end
    return original_fs_stat(path, ...)
  end

  local ok, err = pcall(function()
    fs.find_files(dir, { sort_by = "path" })
  end)
  vim.uv.fs_stat = original_fs_stat
  if not ok then
    error(err)
  end

  eq(result_stats, 0)
end

return T
