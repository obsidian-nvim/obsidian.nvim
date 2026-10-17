local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["link picker preserves live occurrences and previews source context"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["note.md"] = "[[On disk]]\n",
  })

  local result = h.child_await(
    child,
    [=[
    local path = tostring(Obsidian.dir / "note.md")
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[Unsaved]]" })

    local picker = require "obsidian.picker"
    picker.select = function(items, opts, on_choice)
      local spec = opts.preview_item(items[1])
      _G.preview_line = vim.api.nvim_buf_get_lines(spec.buf, 1, 2, false)[1]
      on_choice({ items[1] })
    end
    require("obsidian.interfaces.links").pick({}, function(matches)
      done {
        link = matches[1].link,
        path = matches[1].path,
        line = matches[1].line,
      }
    end)
  ]=],
    { desc = "live link picker" }
  )

  local root = child.lua_get [[tostring(Obsidian.dir)]]
  eq("[[Unsaved]]", result.link)
  eq(vim.fs.joinpath(root, "note.md"), result.path)
  eq(1, result.line)
  eq("[[Unsaved]]", child.lua_get [[preview_line]])
end

T["Links picker excludes footnote references"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["footnotes.md"] = "[[target]] and [^source]\n[^source]: Footnote body\n",
  })

  local links = h.child_await(
    child,
    [[
    local path = tostring(Obsidian.dir / "footnotes.md")
    vim.cmd.edit(vim.fn.fnameescape(path))
    local picker = require "obsidian.picker"
    picker.select = function(items, _, on_choice)
      _G.links_labels = vim.tbl_map(function(item)
        return item.user_data.link
      end, items)
      on_choice({ items[1] })
    end
    require("obsidian.interfaces.links").pick({}, function(matches)
      done(vim.tbl_map(function(match)
        return match.link
      end, matches))
    end)
  ]],
    { desc = "Links excludes footnotes" }
  )

  eq({ "[[target]]" }, links)
  eq({ "[[target]]" }, child.lua_get [[links_labels]])
end

T["link target resolution is read-only and distinguishes URL, note, and missing"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[Target#Heading]]\n[[missing]]\n",
    ["Target.md"] = "# Heading\nTarget body\n",
  })

  local result = h.child_await(
    child,
    [=[
    local link = require "obsidian.link"
    local source = tostring(Obsidian.dir / "source.md")
    local source_buf = vim.fn.bufadd(source)
    vim.fn.bufload(source_buf)
    local before = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)

    link.resolve_target_async("[[Target#Heading]]", {
      bufnr = source_buf,
      source_path = source,
      workspace_dir = tostring(Obsidian.dir),
    }, function(target)
      _G.note_target = { kind = target.kind, path = target.notes and tostring(target.notes[1].path) }
      link.resolve_target_async("[[missing]]", {
        bufnr = source_buf,
        source_path = source,
        workspace_dir = tostring(Obsidian.dir),
      }, function(missing)
        _G.missing_target = { kind = missing.kind, path = missing.path }
        link.resolve_target_async("<https://example.com>", {
          bufnr = source_buf,
          source_path = source,
          workspace_dir = tostring(Obsidian.dir),
        }, function(url)
          done {
            note = note_target,
            missing = missing_target,
            url = { kind = url.kind, url = url.url },
            before = before,
            after = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false),
          }
        end)
      end)
    end)
  ]=],
    { desc = "read-only link resolution" }
  )

  local root = child.lua_get [[tostring(Obsidian.dir)]]
  eq("note", result.note.kind)
  eq(vim.fs.joinpath(root, "Target.md"), result.note.path)
  eq("missing", result.missing.kind)
  eq(true, result.missing.path ~= nil)
  eq({ kind = "url", url = "https://example.com" }, result.url)
  eq(result.before, result.after)
end

return T
