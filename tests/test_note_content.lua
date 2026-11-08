local h = dofile "tests/helpers.lua"
local Note = require "obsidian.note"
local eq = MiniTest.expect.equality
local T = h.temp_vault

local function existing(content)
  local path = Obsidian.dir / "Content.md"
  h.write(content, path)
  return Note.from_file(path), path
end

T["body insertion supports all spacing modes in both directions"] = function()
  for _, case in ipairs {
    { "bot", "auto", { "old", "", "new" }, 3, 0 },
    { "bot", "newline", { "old", "new" }, 2, 0 },
    { "bot", "inline", { "oldnew" }, 1, 3 },
    { "top", "auto", { "new", "", "old" }, 1, 0 },
    { "top", "newline", { "new", "old" }, 1, 0 },
    { "top", "inline", { "newold" }, 1, 0 },
  } do
    local note, path = existing "old"
    local row, col = note:insert_text("new", {
      target = "body",
      placement = case[1],
      spacing = case[2],
      insert_frontmatter = false,
    })
    eq(case[3], h.read(path))
    eq({ case[4], case[5] }, { row, col })
  end
end

T["body and preamble are distinct targets"] = function()
  local note, path = existing "intro\n# Heading\nbody"
  note:insert_text("preamble", { placement = "bot", insert_frontmatter = false })
  eq({ "intro", "preamble", "", "# Heading", "body" }, h.read(path))
  note:insert_text("end", { target = "body", placement = "bot", spacing = "newline", insert_frontmatter = false })
  eq({ "intro", "preamble", "", "# Heading", "body", "end" }, h.read(path))
end

T["section append can include or exclude descendants"] = function()
  for _, children in ipairs { false, true } do
    local note, path = existing "## Log\nold\n### Child\nchild\n\n## Other\nuntouched"
    note:insert_text("new", {
      section = "log",
      ignore_case = true,
      include_children = children,
      placement = "bot",
      spacing = "auto",
      insert_frontmatter = false,
    })
    local expected = children and { "## Log", "old", "### Child", "child", "", "new", "", "## Other", "untouched" }
      or { "## Log", "old", "", "new", "", "### Child", "child", "", "## Other", "untouched" }
    eq(expected, h.read(path))
  end
end

T["descendant append also supports the legacy spacing rules"] = function()
  local note, path = existing "## Parent\n### Child\nchild\n## Other"
  note:insert_text("new", {
    section = "Parent",
    placement = "bot",
    include_children = true,
    insert_frontmatter = false,
  })
  eq({ "## Parent", "### Child", "child", "new", "", "## Other" }, h.read(path))
end

T["section prepend preserves leading blank lines"] = function()
  local note, path = existing "## Tasks\n\nold\n\n## Other"
  note:insert_text("new", { section = "Tasks", spacing = "auto", insert_frontmatter = false })
  eq({ "## Tasks", "", "new", "", "old", "", "## Other" }, h.read(path))
end

T["section spacing supports newline and inline"] = function()
  for _, case in ipairs {
    { "bot", "newline", { "## Log", "old", "new", "", "## Other" } },
    { "bot", "inline", { "## Log", "oldnew", "", "## Other" } },
    { "top", "newline", { "## Log", "new", "old", "", "## Other" } },
    { "top", "inline", { "## Log", "newold", "", "## Other" } },
  } do
    local note, path = existing "## Log\nold\n\n## Other"
    note:insert_text("new", { section = "Log", placement = case[1], spacing = case[2], insert_frontmatter = false })
    eq(case[3], h.read(path))
  end
end

T["section selection uses the first real heading including setext"] = function()
  local note, path = existing "```md\n## Log\n```\nLog\n---\nfirst\n## Log\nsecond"
  note:insert_text("new", { section = "Log", placement = "bot", spacing = "newline", insert_frontmatter = false })
  eq({ "```md", "## Log", "```", "Log", "---", "first", "new", "## Log", "second" }, h.read(path))
end

T["empty section insertion preserves padding"] = function()
  local note, path = existing "## Log\n\n## Other"
  note:insert_text("new", { section = "Log", placement = "bot", spacing = "newline", insert_frontmatter = false })
  eq({ "## Log", "", "new", "## Other" }, h.read(path))
end

T["case-insensitive section matching supports Unicode"] = function()
  local note, path = existing "## ÉTÉ\nold"
  note:insert_text("new", {
    section = "été",
    ignore_case = true,
    placement = "bot",
    spacing = "newline",
    insert_frontmatter = false,
  })
  eq({ "## ÉTÉ", "old", "new" }, h.read(path))
end

T["spacing reuses existing and incoming newlines"] = function()
  local note, path = existing "old\n"
  note:insert_text("\nnew", { target = "body", placement = "bot", spacing = "auto", insert_frontmatter = false })
  eq({ "old", "", "new" }, h.read(path))
  note, path = existing "## Log\nold\n## Other"
  note:insert_text("new\n", { section = "Log", placement = "bot", spacing = "auto", insert_frontmatter = false })
  eq({ "## Log", "old", "", "new", "", "## Other" }, h.read(path))
end

T["empty insertion is a no-op"] = function()
  local note, path = existing "## Log\nold\n## Other"
  local row, col = note:insert_text("", { section = "Log", spacing = "auto", insert_frontmatter = false })
  eq({ 0, 0 }, { row, col })
  eq({ "## Log", "old", "## Other" }, h.read(path))
end

T["multiline strings and arrays produce the same edit"] = function()
  for _, text in ipairs { "first\nsecond", { "first", "second" } } do
    local note, path = existing "old"
    note:insert_text(text, { target = "body", placement = "bot", spacing = "newline", insert_frontmatter = false })
    eq({ "old", "first", "second" }, h.read(path))
  end
end

T["insertion forwards save options and reports positions after frontmatter"] = function()
  local note, path = existing "---\nstatus: kept\n---\nold"
  local target = Obsidian.dir / "Copy.md"
  local row, col = note:insert_text("new", {
    target = "body",
    placement = "bot",
    spacing = "inline",
    path = target,
    insert_frontmatter = false,
    check_buffers = false,
  })
  eq({ 4, 3 }, { row, col })
  eq({ "---", "status: kept", "---", "oldnew" }, h.read(target))
  eq({ "---", "status: kept", "---", "old" }, h.read(path))
end

T["missing section error leaves the file unchanged"] = function()
  local note, path = existing "## Log\nold"
  MiniTest.expect.error(function()
    note:insert_text("new", { section = "Missing", on_section_missing = "error", spacing = "auto" })
  end)
  eq({ "## Log", "old" }, h.read(path))
end

T["save replaces content without templates or managed frontmatter"] = function()
  local note, path = existing "---\nstatus: kept\n---\nold"
  local written = note:save { content = "new\nbody", insert_frontmatter = false }
  eq({ "---", "status: kept", "---", "new", "body" }, written)
  eq(written, h.read(path))
end

T["empty replacement clears the body but preserves frontmatter"] = function()
  local note, path = existing "---\nstatus: kept\n---\nold"
  note:save { content = "", insert_frontmatter = false }
  eq({ "---", "status: kept", "---" }, h.read(path))
end

T["exact creation bypasses ID and path transforms and runs lifecycle once"] = function()
  local calls = 0
  Obsidian.opts.note_id_func = function()
    error "ID transform must not run"
  end
  Obsidian.opts.note_path_func = function()
    error "Path transform must not run"
  end
  local original = Obsidian.opts.callbacks.create_note
  Obsidian.opts.callbacks.create_note = function(_, opts)
    eq("test", opts.scope)
    calls = calls + 1
  end
  local path = Obsidian.dir / "Nested" / "Exact.md"
  eq(path, Note.resolve_path { path = path })
  eq(0, calls)
  local note = Note.create { path = path, scope = "test", prompt_invalid_filename = false }
  eq(path, note.path)
  eq(1, calls)
  eq(false, path:exists())
  note:save { content = "exact", insert_frontmatter = false }
  eq({ "exact" }, h.read(path))
  Obsidian.opts.callbacks.create_note = original
end

T["noninteractive path resolution rejects invalid names without prompting"] = function()
  MiniTest.expect.error(function()
    Note.resolve_path { id = "bad:name", verbatim = true }
  end)
  MiniTest.expect.error(function()
    Note.create { path = "relative.md" }
  end)
end

local C, child = h.child_vault()
T["buffer operations"] = C

C["insertion uses unsaved body and frontmatter for returned positions"] = function()
  local result = child.lua [[
    local Note = require "obsidian.note"
    local path = Obsidian.dir / "Content.md"
    vim.fn.writefile({ "old" }, tostring(path))
    local note = Note.from_file(path)
    vim.cmd.edit(tostring(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "---", "status: unsaved", "---", "## Log", "unsaved" })
    local row, col = note:insert_text("new", {
      section = "Log", placement = "bot", spacing = "inline", insert_frontmatter = false,
    })
    return { row, col, vim.fn.readfile(tostring(path)), vim.api.nvim_buf_get_lines(0, 0, -1, false) }
  ]]
  eq({ 5, 7 }, { result[1], result[2] })
  eq({ "---", "status: unsaved", "---", "## Log", "unsavednew" }, result[3])
  eq(result[3], result[4])
end

C["open resolves navigation against a changed buffer"] = function()
  local result = child.lua [[
    local Note = require "obsidian.note"
    local path = Obsidian.dir / "Content.md"
    vim.fn.writefile({ "## Old", "old" }, tostring(path))
    local note = Note.from_file(path)
    vim.cmd.edit(tostring(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "intro", "## New", "body ^block" })
    note:open { sync = true, anchor = "New" }
    local heading = vim.api.nvim_win_get_cursor(0)[1]
    note:open { sync = true, block = "block" }
    local block = vim.api.nvim_win_get_cursor(0)[1]
    note:open { sync = true, block = "missing" }
    return { heading, block, vim.api.nvim_buf_get_name(0) == tostring(path) }
  ]]
  eq({ 2, 3, true }, result)
end

return T
