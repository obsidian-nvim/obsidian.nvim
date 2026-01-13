local MiniTest = require "mini.test"
local Obsidian = require "obsidian"

local T = MiniTest.new_set()

local Helpers = {}

function Helpers.write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(content, "\n"), path)
end

-- Hooks

T.hooks = {
  pre_case = function()
    -- create temporary vault
    Helpers.temp_dir = vim.fn.tempname()
    vim.fn.mkdir(Helpers.temp_dir, "p")

    -- target note
    local a_md = table.concat({
      "# A",
      "## Section",
      "Paragraph with block ^block-id",
      "==highlighted text==",
      "## test",
    }, "\n")
    Helpers.write_file(Helpers.temp_dir .. "/A.md", a_md)

    -- source note with all types + anchors + multiple links per line
    local b_md = table.concat({
      "[[A]] [[A|Alias]] [A](A.md)",
      "[A test](A.md#test) [Another](A.md#Section)",
      "https://example.com/A.md file:///vault/A.md mailto:test@example.com",
      "#A ^block-id ==highlighted text==",
      "[[A#Section]] [[A#^block-id]]",
      "Multiple links on one line: [[A]] [md](A.md#test) [[A#Section]]",
    }, "\n")
    Helpers.write_file(Helpers.temp_dir .. "/B.md", b_md)

    -- obsidian.nvim setup (workspaces REQUIRED)
    Obsidian.setup {
      workspaces = {
        { name = "test", path = Helpers.temp_dir },
      },
      disable_frontmatter = true,
    }

    -- index vault for backlinks
    Obsidian.get_client():scan()
  end,

  post_case = function()
    vim.fn.delete(Helpers.temp_dir, "rf")
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

-- Tests

T["detects all RefTypes"] = function()
  local noteA = Obsidian.get_client():find_note "A"
  assert(noteA ~= nil, "No Note A Found")

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
  local noteA = Obsidian.get_client():find_note "A"

  -- Header anchor Section (wiki + markdown)
  local section_links = noteA:backlinks { anchor = "Section" }
  assert(#section_links == 3, "Expected 3 links to Section")

  for _, m in ipairs(section_links) do
    assert(m.ref.anchor == "Section", "Anchor mismatch: " .. tostring(m.ref.anchor))
    assert(
      m.ref.type == "HeaderLink" or m.ref.type == "Markdown",
      "Unexpected ref type for Section anchor: " .. tostring(m.ref.type)
    )
  end

  -- Markdown anchor 'test'
  local test_links = noteA:backlinks { anchor = "test" }
  assert(#test_links == 2, "Expected 2 links to 'test' anchor")

  for _, m in ipairs(test_links) do
    assert(m.ref.anchor == "test", "Anchor mismatch: " .. tostring(m.ref.anchor))
    assert(m.ref.type == "Markdown", "Expected Markdown type for test anchor")
  end
end

T["multiple links per line"] = function()
  local noteA = Obsidian.get_client():find_note "A"
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
