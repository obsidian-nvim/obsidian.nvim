local MiniTest = require "mini.test"
local Obsidian = require "obsidian"
local api = require "obsidian.api"

local T = MiniTest.new_set()

-- Local helpers
local Helpers = {}

function Helpers.write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(content, "\n"), path)
end

-- Hooks
T.hooks = {
  pre_case = function()
    Helpers.temp_dir = vim.fn.tempname()
    vim.fn.mkdir(Helpers.temp_dir, "p")
    -- Fix: Create templates dir to silence the 'templates' error
    vim.fn.mkdir(Helpers.temp_dir .. "/templates", "p")

    -- Target note
    local a_md = table.concat({
      "# A",
      "## Section",
      "Paragraph with block ^block-id",
      "==highlighted text==",
      "## test",
    }, "\n")
    Helpers.write_file(Helpers.temp_dir .. "/A.md", a_md)

    -- Source note
    local b_md = table.concat({
      "[[A]] [[A|Alias]] [A](A.md)",
      "[A test](A.md#test) [Another](A.md#Section)",
      "https://example.com/A.md file:///vault/A.md mailto:test@example.com",
      "#A ^block-id ==highlighted text==",
      "[[A#Section]] [[A#^block-id]]",
      "Multiple links on one line: [[A]] [md](A.md#test) [[A#Section]]",
    }, "\n")
    Helpers.write_file(Helpers.temp_dir .. "/B.md", b_md)

    Obsidian.setup {
      workspaces = { { name = "test", path = Helpers.temp_dir } },
      templates = { subdir = "templates" }, -- Fix: Explicitly point to the created dir
      disable_frontmatter = true,
    }

    Obsidian.get_client():scan()
    vim.cmd.edit(Helpers.temp_dir .. "/A.md")

    -- Fix: In headless mode, we must manually trigger the buffer logic
    -- because 'BufEnter' doesn't always fire reliably in CI.
    Obsidian.get_client():_on_buf_enter(0)
  end,

  post_case = function()
    vim.fn.delete(Helpers.temp_dir, "rf")
    vim.cmd.bwipeout { force = true }
  end,
}

-- Utility: check backlinks
local function has(backlinks, opts)
  for _, m in ipairs(backlinks) do
    local ok = true
    if opts.type and m.ref.type ~= opts.type then
      ok = false
    end
    if opts.anchor and m.ref.anchor ~= opts.anchor then
      ok = false
    end
    if ok then
      return true
    end
  end
  return false
end

-- Fix: Use a helper to get the note reliably
local function get_test_note()
  local client = Obsidian.get_client()
  -- If api.current_note fails, we fetch it directly by path
  local note = api.current_note(0, { collect_anchor_links = true }) or client:get_note(Helpers.temp_dir .. "/A.md")

  if note then
    note:update_metadata { collect_anchor_links = true }
  end
  return note
end

-- Tests
T["detects all RefTypes"] = function()
  local noteA = get_test_note()
  assert(noteA ~= nil, "No current Obsidian note")

  local backlinks = noteA:backlinks()
  local expected = {
    "Wiki",
    "WikiWithAlias",
    "Markdown",
    "NakedUrl",
    "FileUrl",
    "MailtoUrl",
    "Tag",
    "BlockID",
    "Highlight",
    "HeaderLink",
    "BlockLink",
  }

  for _, t in ipairs(expected) do
    assert(has(backlinks, { type = t }), "Missing backlink ref type: " .. t)
  end
end

T["anchor filtering works"] = function()
  local noteA = get_test_note()
  assert(noteA ~= nil, "No current Obsidian note")

  local section_links = noteA:backlinks { anchor = "Section" }
  assert(#section_links == 3, "Expected 3 links to Section")

  for _, m in ipairs(section_links) do
    assert(m.ref.anchor == "Section", "Anchor mismatch: " .. tostring(m.ref.anchor))
  end

  local test_links = noteA:backlinks { anchor = "test" }
  assert(#test_links == 2, "Expected 2 links to 'test' anchor")
end

T["multiple links per line"] = function()
  local noteA = get_test_note()
  assert(noteA ~= nil, "No current Obsidian note")

  local backlinks = noteA:backlinks()
  local by_line = {}
  for _, m in ipairs(backlinks) do
    by_line[m.lnum] = (by_line[m.lnum] or 0) + 1
  end

  local has_multi = false
  for _, count in pairs(by_line) do
    if count > 1 then
      has_multi = true
      break
    end
  end
  assert(has_multi, "Expected multiple backlinks on a single line")
end

return T
