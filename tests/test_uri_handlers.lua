local h = dofile "tests/helpers.lua"
local uri = require "obsidian.uri"
local eq = MiniTest.expect.equality

local T = h.temp_vault

local function with_mock(object, key, replacement, run)
  local original = object[key]
  object[key] = replacement
  local ok, result = pcall(run)
  object[key] = original
  assert(ok, result)
  return result
end

local function plain_notes()
  Obsidian.opts.frontmatter.enabled = false
  Obsidian.opts.note.template = nil
end

T["new persists an exact nested file silently"] = function()
  plain_notes()
  local result = uri.handle "obsidian://new?file=Clippings%2FPage%20Title&content=hello%26world&silent"
  local path = Obsidian.dir / "Clippings" / "Page Title.md"

  eq(true, result.ok)
  eq(true, path:is_file())
  eq({ "hello&world" }, h.read(path))
  eq(false, vim.api.nvim_buf_get_name(0) == tostring(path))
end

T["new content does not gain plugin frontmatter or a template"] = function()
  local result = uri.handle "obsidian://new?name=Clipped&content=%23%20Clipped&silent"

  eq(true, result.ok)
  eq({ "# Clipped" }, h.read(Obsidian.dir / "Clipped.md"))
end

T["new creates an empty note when silent"] = function()
  plain_notes()
  local result = uri.handle "obsidian://new?name=Empty&silent"

  eq(true, result.ok)
  eq(true, (Obsidian.dir / "Empty.md"):is_file())
end

T["new leaves existing content unchanged without a mutation flag"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  local result = uri.handle "obsidian://new?file=Existing&content=new&silent"

  eq(true, result.ok)
  eq({ "old" }, h.read(path))
end

T["new appends and append takes precedence over overwrite"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&append&overwrite&silent"

  eq({ "old", "", "new" }, h.read(path))
end

T["new prepends content"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&prepend&silent"

  eq({ "new", "", "old" }, h.read(path))
end

T["new overwrites content"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&overwrite&silent"

  eq({ "new" }, h.read(path))
end

T["new rejects traversal outside the workspace"] = function()
  plain_notes()
  local outside = assert(Obsidian.dir:parent(), "temporary vault parent is required") / "outside.md"
  local result = uri.handle "obsidian://new?file=..%2Foutside&content=nope&silent"

  eq(false, result.ok)
  eq(false, outside:exists())
end

T["daily persists content without opening"] = function()
  plain_notes()
  local result = uri.handle "obsidian://daily?content=journal&silent"

  eq(true, result.ok)
  eq(true, result.note:exists())
  eq({ "journal" }, h.read(result.note.path))
  eq(false, vim.api.nvim_buf_get_name(0) == tostring(result.note.path))
end

T["unique uses the configured unique folder"] = function()
  plain_notes()
  Obsidian.opts.unique_note.folder = "unique"
  Obsidian.opts.unique_note.template = nil
  local unique_dir = Obsidian.dir / "unique"
  unique_dir:mkdir()

  local result = uri.handle "obsidian://unique?content=unique%20body"

  eq(true, result.ok)
  eq(unique_dir, result.note.path:parent())
  eq({ "unique body" }, h.read(result.note.path))
end

T["open navigates to block lines"] = function()
  plain_notes()
  local path = Obsidian.dir / "Blocks.md"
  h.write("first\ntarget ^block", path)

  local result = uri.handle "obsidian://open?file=Blocks%23%5Eblock"

  eq(true, result.ok)
  eq(2, vim.api.nvim_win_get_cursor(0)[1])
end

T["open supports paneType tab"] = function()
  plain_notes()
  h.write("body", Obsidian.dir / "Tabbed.md")

  local result = uri.handle "obsidian://open?file=Tabbed&paneType=tab"

  eq(true, result.ok)
  eq(2, #vim.api.nvim_list_tabpages())
end

T["path overrides an invalid vault"] = function()
  plain_notes()
  local path = Obsidian.dir / "Absolute.md"
  h.write("body", path)
  local encoded = vim.uri_encode(tostring(path), "rfc2396")

  local result = uri.handle("obsidian://open?vault=missing&path=" .. encoded)

  eq(true, result.ok)
  eq(tostring(path), vim.api.nvim_buf_get_name(0))
end

T["absolute paths select the most specific workspace"] = function()
  plain_notes()
  local original = Obsidian.workspace
  local nested_dir = Obsidian.dir / "nested"
  nested_dir:mkdir()
  local nested = require("obsidian.workspace").new {
    name = "nested",
    path = nested_dir,
    strict = true,
  }
  assert(nested, "nested workspace is required")
  table.insert(Obsidian.workspaces, nested)
  local path = nested_dir / "Specific.md"
  h.write("body", path)

  local ok, result = pcall(uri.handle, "obsidian://open?path=" .. vim.uri_encode(tostring(path), "rfc2396"))
  require("obsidian.workspace").set(original)

  assert(ok, result)
  eq(true, result.ok)
  eq("nested", result.note.path:parent().name)
end

T["markdown URI handling preserves encoded query delimiters"] = function()
  Obsidian.opts.uri.require_confirmation = false
  local definition = require "obsidian.lsp.handlers._definition"
  local received
  local original = uri.handle
  uri.handle = function(value)
    received = value
    return {
      ok = true,
      action = "new",
      interactive = false,
      silent = false,
    }
  end

  local ok, err = pcall(function()
    definition.follow_link("[URI](obsidian://new?content=a%26b%3Dc)", function() end)
  end)
  uri.handle = original

  assert(ok, err)
  eq("obsidian://new?content=a%26b%3Dc", received)
end

T["markdown mutating URIs require confirmation"] = function()
  Obsidian.opts.uri.require_confirmation = true
  local definition = require "obsidian.lsp.handlers._definition"
  local api = require "obsidian.api"
  local handled = false
  local original_handle = uri.handle
  local original_confirm = api.confirm
  uri.handle = function()
    handled = true
    return {
      ok = true,
      action = "new",
      interactive = false,
      silent = false,
    }
  end
  api.confirm = function()
    return "No"
  end

  local ok, err = pcall(function()
    definition.follow_link("[URI](obsidian://new?name=Blocked)", function() end)
  end)
  uri.handle = original_handle
  api.confirm = original_confirm

  assert(ok, err)
  eq(false, handled)
end

T["unsupported actions return an error result"] = function()
  local result = uri.handle "obsidian://unknown?value=1"
  eq(false, result.ok)
  eq("unknown", result.action)
end

T["append heading includes descendants but not the next sibling"] = function()
  plain_notes()
  local path = Obsidian.dir / "Sections.md"
  h.write("## Log\nold\n### Child\nchild\n\n## Other\nuntouched", path)

  local result = uri.handle "obsidian://new?file=Sections&append&silent&heading=log&content=new"

  eq(true, result.ok)
  eq({ "## Log", "old", "### Child", "child", "", "new", "", "## Other", "untouched" }, h.read(path))
end

T["missing heading returns an error without changing existing content"] = function()
  plain_notes()
  local path = Obsidian.dir / "Sections.md"
  h.write("## Log\nold", path)

  local result = uri.handle "obsidian://new?file=Sections&append&silent&heading=Missing&content=new"

  eq(false, result.ok)
  eq(true, result.error:find("Missing", 1, true) ~= nil)
  eq({ "## Log", "old" }, h.read(path))
end

T["heading defaults to append even with overwrite"] = function()
  plain_notes()
  local path = Obsidian.dir / "Sections.md"
  for _, flags in ipairs { "", "&overwrite" } do
    h.write("## Log\nold\n## Other", path)
    local result = uri.handle("obsidian://new?file=Sections&silent&heading=Log&content=new" .. flags)
    eq(true, result.ok)
    eq({ "## Log", "old", "", "new", "", "## Other" }, h.read(path))
  end
end

T["spacing alone still requires append or prepend"] = function()
  plain_notes()
  local path = Obsidian.dir / "Sections.md"
  h.write("## Log\nold", path)

  local result = uri.handle "obsidian://new?file=Sections&overwrite&silent&content=new&spacing=inline"

  eq(false, result.ok)
  eq({ "## Log", "old" }, h.read(path))
end

T["invalid spacing returns an error without writing"] = function()
  plain_notes()
  local path = Obsidian.dir / "Spacing.md"
  h.write("old", path)

  local result = uri.handle "obsidian://new?file=Spacing&append&spacing=invalid&content=new&silent"

  eq(false, result.ok)
  eq({ "old" }, h.read(path))
end

T["daily heading uses the configured template"] = function()
  plain_notes()
  Obsidian.opts.daily_notes.template = "Daily"
  h.write("## Log\n\n## Tasks", Obsidian.dir / "templates" / "Daily.md")

  local result = uri.handle "obsidian://daily?silent&heading=Log&spacing=newline&content=entry"

  eq(true, result.ok)
  eq({ "## Log", "", "entry", "## Tasks" }, h.read(result.note.path))
end

T["URI insertion translates into the public note API"] = function()
  plain_notes()
  h.write("## Log\nold", Obsidian.dir / "Sections.md")
  local received
  local Note = require "obsidian.note"
  local result = with_mock(Note, "insert_text", function(_, content, opts)
    received = { content = content, opts = opts }
  end, function()
    return uri.handle "obsidian://new?file=Sections&heading=%23%23%20Log&prepend&spacing=inline&content=new&silent"
  end)
  eq(true, result.ok)
  eq("new", received.content)
  eq("Log", received.opts.section)
  eq("section", received.opts.target)
  eq("top", received.opts.placement)
  eq("inline", received.opts.spacing)
  eq(true, received.opts.include_children)
  eq(true, received.opts.ignore_case)
  eq(false, received.opts.insert_frontmatter)
  eq("error", received.opts.on_section_missing)
end

T["dispatch does not mutate its parsed request"] = function()
  plain_notes()
  h.write("## Log\nold", Obsidian.dir / "Sections.md")
  local parsed = uri.parse "obsidian://new?file=Sections&heading=Log&content=new&silent"
  local before = vim.deepcopy(parsed)
  eq(true, uri.dispatch(parsed).ok)
  eq(before, parsed)
end

T["search uses the shared picker API"] = function()
  local received
  local result = with_mock(require "obsidian.picker", "grep_notes", function(opts)
    received = opts.query
  end, function()
    return uri.handle "obsidian://search?query=hello%26world"
  end)
  eq(true, result.ok)
  eq(true, result.interactive)
  eq("hello&world", received)
end

T["URI and command use the same workspace chooser"] = function()
  local calls = 0
  with_mock(require "obsidian.workspace", "pick", function()
    calls = calls + 1
  end, function()
    local result = uri.handle "obsidian://choose-vault"
    eq(true, result.ok)
    eq(true, result.interactive)
    require "obsidian.commands.workspace" { args = "" }
  end)
  eq(2, calls)
end

T["workspace picker excludes internal workspaces and handles cancellation"] = function()
  local Workspace = require "obsidian.workspace"
  local original = Obsidian.workspace
  table.insert(Obsidian.workspaces, { name = ".obsidian.wiki" })
  table.insert(Obsidian.workspaces, original)
  with_mock(require "obsidian.picker", "select", function(items, _, callback)
    eq(2, #items)
    eq(original, items[1].user_data)
    eq(original, items[2].user_data)
    callback(nil)
  end, function()
    Workspace.pick()
  end)
  eq(original, Obsidian.workspace)
end

T["new runs creation lifecycle once and never for an existing file"] = function()
  plain_notes()
  local calls = 0
  with_mock(Obsidian.opts.callbacks, "create_note", function(_, opts)
    eq("uri", opts.scope)
    calls = calls + 1
  end, function()
    eq(true, uri.handle("obsidian://new?file=Exact&content=body&silent").ok)
    eq(1, calls)
    eq(true, uri.handle("obsidian://new?file=Exact&content=more&append&silent").ok)
    eq(1, calls)
    eq(false, uri.handle("obsidian://new?file=..%2Foutside&silent").ok)
    eq(1, calls)
  end)
end

T["unique URI creates its folder without prompting"] = function()
  plain_notes()
  Obsidian.opts.unique_note.folder = "new-unique-folder"
  Obsidian.opts.unique_note.template = nil
  local result = with_mock(require "obsidian.api", "confirm", function()
    error "URI must not prompt for folder creation"
  end, function()
    return uri.handle "obsidian://unique?content=body"
  end)
  eq(true, result.ok)
  eq({ "body" }, h.read(result.note.path))
  eq("new-unique-folder", result.note.path:parent().name)
end

local C, child = h.child_vault()
T["internal navigation"] = C

C["daily unique and search honor the URI vault rather than the source buffer"] = function()
  local result = child.lua [[
    local Workspace = require "obsidian.workspace"
    local original = Obsidian.workspace
    local target_path = original.root / "other"
    target_path:mkdir()
    local target = Workspace.new { name = "target", path = target_path, strict = true }
    table.insert(Obsidian.workspaces, target)
    local source = original.root / "Source.md"
    vim.fn.writefile({ "source" }, tostring(source))
    vim.cmd.edit(tostring(source))
    local uri = require "obsidian.uri"
    local search_dir
    require("obsidian.picker").grep_notes = function(opts)
      search_dir = opts.dir
    end
    local search = uri.handle "obsidian://search?vault=target&query=text"
    local daily = uri.handle "obsidian://daily?vault=target&content=daily&silent"
    local unique = uri.handle "obsidian://unique?vault=target&content=unique"
    return {
      daily.ok,
      unique.ok,
      target_path:is_parent_of(daily.note.path),
      target_path:is_parent_of(unique.note.path),
      search.ok,
      search_dir == target_path,
    }
  ]]
  eq({ true, true, true, true, true, true }, result)
end

C["follow_link opens headings and blocks internally"] = function()
  local result = child.lua [[
    local target = Obsidian.dir / "Target.md"
    local source = Obsidian.dir / "Source.md"
    vim.fn.writefile({ "intro", "## Heading", "body ^block" }, tostring(target))
    vim.fn.writefile({ "[Target](obsidian://open?file=Target%23Heading)" }, tostring(source))
    vim.cmd.edit(tostring(source))
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    local external = 0
    vim.ui.open = function()
      external = external + 1
    end
    local actions = require "obsidian.actions"
    actions.follow_link()
    local heading = vim.api.nvim_win_get_cursor(0)[1]
    actions.follow_link "<obsidian://open?file=Target%23%5Eblock>"
    return { vim.api.nvim_buf_get_name(0) == tostring(target), heading, vim.api.nvim_win_get_cursor(0)[1], external }
  ]]
  eq({ true, 2, 3, 0 }, result)
end

C["follow_link confirms writes and preserves encoded content"] = function()
  local result = child.lua [[
    local source = Obsidian.dir / "Source.md"
    vim.fn.writefile({ "source" }, tostring(source))
    vim.cmd.edit(tostring(source))
    local prompts, external = 0, 0
    local api = require "obsidian.api"
    api.confirm = function()
      prompts = prompts + 1
      return "Yes"
    end
    vim.ui.open = function()
      external = external + 1
    end
    local actions = require "obsidian.actions"
    actions.follow_link "[Capture](obsidian://new?file=Captured&content=a%26b%3Dc&silent)"
    local content = vim.fn.readfile(tostring(Obsidian.dir / "Captured.md"))
    api.confirm = function()
      prompts = prompts + 1
      return "No"
    end
    actions.follow_link "[Blocked](obsidian://new?vault=missing&file=Blocked&content=nope&silent)"
    return {
      content, prompts, external,
      (Obsidian.dir / "Blocked.md"):exists(),
      vim.api.nvim_buf_get_name(0) == tostring(source),
    }
  ]]
  eq({ { "a&b=c" }, 2, 0, false, true }, result)
end

C["search and workspace URIs use internal pickers through navigation"] = function()
  local result = child.lua [[
    local grep, choose, external = 0, 0, 0
    require("obsidian.picker").grep_notes = function(opts)
      assert(opts.query == "a&b", "query must stay encoded until parsing")
      grep = grep + 1
    end
    require("obsidian.workspace").pick = function()
      choose = choose + 1
    end
    vim.ui.open = function()
      external = external + 1
    end
    local actions = require "obsidian.actions"
    actions.follow_link "[Search](obsidian://search?query=a%26b)"
    actions.follow_link "<obsidian://choose-vault>"
    return { grep, choose, external }
  ]]
  eq({ 1, 1, 0 }, result)
end

C["daily and unique links run internally after confirmation"] = function()
  local result = child.lua [[
    local source = Obsidian.dir / "Source.md"
    vim.fn.writefile({ "source" }, tostring(source))
    vim.cmd.edit(tostring(source))
    Obsidian.opts.frontmatter.enabled = false
    Obsidian.opts.daily_notes.template = nil
    Obsidian.opts.unique_note.template = nil
    local prompts, external = 0, 0
    require("obsidian.api").confirm = function()
      prompts = prompts + 1
      return "Yes"
    end
    vim.ui.open = function()
      external = external + 1
    end
    local actions = require "obsidian.actions"
    actions.follow_link "<obsidian://daily?content=journal&silent>"
    local daily = require("obsidian.daily").daily_note_path(os.time(), Obsidian.workspace.root)
    local journal = vim.fn.readfile(tostring(daily))
    actions.follow_link "[Unique](obsidian://unique?content=unique)"
    return {
      prompts, external, journal,
      vim.fn.readfile(vim.api.nvim_buf_get_name(0)),
      vim.api.nvim_buf_get_name(0) ~= tostring(source),
    }
  ]]
  eq({ 2, 0, { "journal" }, { "unique" }, true }, result)
end

C["disabling internal URI handling preserves external opening policy"] = function()
  local result = child.lua [[
    Obsidian.opts.uri.enabled = false
    local received, prompts
    prompts = 0
    vim.ui.open = function(value)
      received = value
    end
    require("obsidian.api").confirm = function()
      prompts = prompts + 1
      return "Yes"
    end
    require("obsidian.actions").follow_link "[External](obsidian://open?file=Note)"
    return { received, prompts }
  ]]
  eq({ "obsidian://open?file=Note", 1 }, result)
end

C["external integration parameters do not launch applications"] = function()
  local result = child.lua [[
    local external = 0
    vim.ui.open = function()
      external = external + 1
    end
    require("obsidian.api").confirm = function()
      return "Yes"
    end
    local actions = require "obsidian.actions"
    actions.follow_link "[Create](obsidian://new?file=Internal&content=body&silent&x-success=test%3A%2F%2Fdone)"
    actions.follow_link "[Hook](obsidian://hook-get-address?x-error=test%3A%2F%2Ferror)"
    return { external, vim.fn.readfile(tostring(Obsidian.dir / "Internal.md")) }
  ]]
  eq({ 0, { "body" } }, result)
end

return T
