local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_cache()
  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
end

-- Lua code (run inside child) that scans all cached notes for mentions of self_symbols.
-- Returns a list of { text, lnum } tables.
local scan_incoming_lua = [[
  (function()
    local ls    = require "obsidian.note.link_suggestion"
    local Note  = require "obsidian.note"
    local cache = require "obsidian.cache"

    local current_path = vim.api.nvim_buf_get_name(0)
    local all_symbols  = ls.symbols(current_path, { include_current = true })
    local self_symbols = {}
    for _, sym in ipairs(all_symbols) do
      for _, tp in ipairs(sym.target_paths) do
        if vim.fs.normalize(tp) == vim.fs.normalize(current_path) then
          self_symbols[#self_symbols + 1] = sym
          break
        end
      end
    end

    local function scan_note(path)
      local raw_file = io.open(path, "r")
      if not raw_file then return {} end
      local raw_content = raw_file:read "*a"
      raw_file:close()
      local has_candidate = false
      for _, sym in ipairs(self_symbols) do
        if raw_content:lower():find(sym.text_lower, 1, true) then
          has_candidate = true ; break
        end
      end
      if not has_candidate then return {} end
      local ok_note, other_note = pcall(Note.from_file, path)
      if not ok_note then return {} end
      local fm_end = other_note.frontmatter_end_line or 1
      local source_dir = vim.fs.dirname(vim.fs.normalize(path))
      local code_fence = nil
      local results = {}
      for row = fm_end, #other_note.contents do
        local line = other_note.contents[row]
        local fence = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
        if fence then
          if not code_fence then code_fence = fence
          elseif fence:sub(1,1) == code_fence:sub(1,1) and #fence >= #code_fence then code_fence = nil end
        elseif not code_fence then
          local sug = ls.find_in_line(line, row, self_symbols, function(p) return vim.uv.fs_stat(p) ~= nil end, source_dir)
          for _, s in ipairs(sug) do
            results[#results + 1] = { text = s.text, col = s.range.start_col, lnum = s.range.start_row + 1 }
          end
        end
      end
      return results
    end

    local results = {}
    for path, _ in pairs(cache.notes.all()) do
      if vim.fs.normalize(path) ~= vim.fs.normalize(current_path) then
        vim.list_extend(results, scan_note(path))
      end
    end
    return results
  end)()
]]

-- ---------------------------------------------------------------------------
-- Outgoing unlinked mentions
-- ---------------------------------------------------------------------------

T["outgoing_links"] = MiniTest.new_set()

T["outgoing_links"]["finds plain-text mention of another note"] = function()
  local root = child.Obsidian.dir
  -- Note stem is "target" which becomes the symbol; source mentions "target" in plain text
  h.write("# Target\n", root / "target.md")
  h.write("# Source\n\nI refer to target in plain text.\n", root / "source.md")
  child.cmd("edit " .. tostring(root / "source.md"))
  setup_cache()

  local suggestions = child.lua_get [[
    (function()
      local api  = require "obsidian.api"
      local ls   = require "obsidian.note.link_suggestion"
      local note = api.current_note(0, { max_lines = vim.api.nvim_buf_line_count(0) })
      local sug  = ls.find(note)
      return vim.tbl_map(function(s) return s.text end, sug)
    end)()
  ]]

  local found = false
  for _, text in ipairs(suggestions) do
    if text:lower() == "target" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["outgoing_links"]["skips already-linked text"] = function()
  local root = child.Obsidian.dir
  h.write("# Target\n", root / "target.md")
  h.write("# Source\n\nAlready linked: [[target]] and also Target in plain.\n", root / "source.md")
  child.cmd("edit " .. tostring(root / "source.md"))
  setup_cache()

  local suggestion_texts = child.lua_get [[
    (function()
      local api  = require "obsidian.api"
      local ls   = require "obsidian.note.link_suggestion"
      local note = api.current_note(0, { max_lines = vim.api.nvim_buf_line_count(0) })
      local sug  = ls.find(note)
      return vim.tbl_map(function(s) return s.text end, sug)
    end)()
  ]]

  for _, text in ipairs(suggestion_texts) do
    assert(not text:find "%[%[", "should not suggest text inside a wikilink: " .. text)
  end
end

T["outgoing_links"]["skips text inside fenced code block"] = function()
  local root = child.Obsidian.dir
  h.write("# Go\n", root / "go.md")
  h.write("# Source\n\n```\nGo is mentioned here\n```\n\nOutside the fence.\n", root / "source.md")
  child.cmd("edit " .. tostring(root / "source.md"))
  setup_cache()

  local suggestions = child.lua_get [[
    (function()
      local api  = require "obsidian.api"
      local ls   = require "obsidian.note.link_suggestion"
      local note = api.current_note(0, { max_lines = vim.api.nvim_buf_line_count(0) })
      return ls.find(note)
    end)()
  ]]

  -- The code fence body is on row index 3 (0-indexed). No suggestion should come from there.
  for _, sug in ipairs(suggestions) do
    assert(sug.range.start_row ~= 3, "suggestion should not come from inside code fence (row 3)")
  end
end

T["outgoing_links"]["skips inline code spans"] = function()
  local root = child.Obsidian.dir
  h.write("# MyNote\n", root / "mynote.md")
  h.write("# Source\n\nUse `MyNote` in code and MyNote outside.\n", root / "source.md")
  child.cmd("edit " .. tostring(root / "source.md"))
  setup_cache()

  local count = child.lua_get [[
    (function()
      local api  = require "obsidian.api"
      local ls   = require "obsidian.note.link_suggestion"
      local note = api.current_note(0, { max_lines = vim.api.nvim_buf_line_count(0) })
      local sug  = ls.find(note)
      local n = 0
      for _, s in ipairs(sug) do
        if s.text:lower() == "mynote" then n = n + 1 end
      end
      return n
    end)()
  ]]

  eq(1, count)
end

-- ---------------------------------------------------------------------------
-- Incoming unlinked mentions (scan logic via link_suggestion directly)
-- ---------------------------------------------------------------------------

T["incoming_links"] = MiniTest.new_set()

T["incoming_links"]["scans other notes for plain-text mentions"] = function()
  local root = child.Obsidian.dir
  h.write("# Alpha\n", root / "alpha.md")
  h.write("# Beta\n\nAlpha is referenced here.\n", root / "beta.md")
  child.cmd("edit " .. tostring(root / "alpha.md"))
  setup_cache()

  local found = child.lua_get(scan_incoming_lua)

  eq(1, #found)
  eq("Alpha", found[1].text)
end

T["incoming_links"]["matches aliases of current note"] = function()
  local root = child.Obsidian.dir
  h.write('---\naliases: ["Al"]\n---\n# Alpha\n', root / "alpha.md")
  h.write("# Beta\n\nAl is a short name.\n", root / "beta.md")
  child.cmd("edit " .. tostring(root / "alpha.md"))
  setup_cache()

  local found = child.lua_get(scan_incoming_lua)

  local found_alias = false
  for _, r in ipairs(found) do
    if r.text == "Al" then
      found_alias = true
    end
  end
  eq(true, found_alias)
end

T["incoming_links"]["does not match text inside existing wikilinks"] = function()
  local root = child.Obsidian.dir
  h.write("# Alpha\n", root / "alpha.md")
  -- beta.md already links to Alpha — only the plain "Alpha" word should be surfaced
  h.write("# Beta\n\n[[Alpha]] and raw Alpha text.\n", root / "beta.md")
  child.cmd("edit " .. tostring(root / "alpha.md"))
  setup_cache()

  local found = child.lua_get(scan_incoming_lua)

  -- Only 1 result: the plain "Alpha" word, not the one inside [[Alpha]]
  eq(1, #found)
end

return T
