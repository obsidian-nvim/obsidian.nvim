local MiniTest = require "mini.test"
local Obsidian = require "obsidian"
local api = require "obsidian.api"

local T = MiniTest.new_set()

-- State and Helpers
local temp_dir
local function write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(content, "\n"), path)
end

T.hooks = {
  pre_case = function()
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.mkdir(temp_dir .. "/templates", "p")

    -- Setup files
    write_file(
      temp_dir .. "/A.md",
      table.concat({
        "# A",
        "## Section",
        "Block ^block-id",
        "==highlight==",
        "## test",
      }, "\n")
    )

    write_file(
      temp_dir .. "/B.md",
      table.concat({
        "[[A]] [[A|Alias]] [A](A.md)",
        "[A test](A.md#test) [Another](A.md#Section)",
        "https://example.com/A.md file:///vault/A.md mailto:test@example.com",
        "#A ^block-id ==highlighted text==",
        "[[A#Section]] [[A#^block-id]]",
        "Multiple links: [[A]] [md](A.md#test) [[A#Section]]",
      }, "\n")
    )

    -- 2. Setup Obsidian
    Obsidian.setup {
      workspaces = { { name = "test", path = temp_dir } },
      templates = { subdir = "templates" },
      disable_frontmatter = true,
    }

    Obsidian.get_client():scan()
    vim.cmd.edit(temp_dir .. "/A.md")
    Obsidian.get_client():_on_buf_enter(0)
  end,

  post_case = function()
    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end
    vim.cmd.bwipeout { force = true }
  end,
}

-- Robust note retrieval
local function get_note_a()
  local client = Obsidian.get_client()
  local note = api.current_note(0) or client:get_note "A"
  if note then
    note:update_metadata { collect_anchor_links = true }
  end
  return note
end

local function has(backlinks, opts)
  for _, m in ipairs(backlinks) do
    if (not opts.type or m.ref.type == opts.type) and (not opts.anchor or m.ref.anchor == opts.anchor) then
      return true
    end
  end
  return false
end

-- Tests
T["detects all RefTypes"] = function()
  local noteA = get_note_a()
  assert(noteA ~= nil, "Note 'A' not found")

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
    assert(has(backlinks, { type = t }), "Missing ref type: " .. t)
  end
end

T["anchor filtering works"] = function()
  local noteA = get_note_a()
  assert(noteA ~= nil, "Note 'A' not found")

  local section_links = noteA:backlinks { anchor = "Section" }
  assert(#section_links == 3, "Expected 3 links to Section, got " .. #section_links)
end

T["multiple links per line"] = function()
  local noteA = get_note_a()
  assert(noteA ~= nil, "Note 'A' not found")

  local backlinks = noteA:backlinks()
  local by_line = {}
  for _, m in ipairs(backlinks) do
    by_line[m.lnum] = (by_line[m.lnum] or 0) + 1
  end

  for _, count in pairs(by_line) do
    if count > 1 then
      return
    end
  end
  error "Expected multiple backlinks on a single line"
end

return T
