---
title: "Folding"
tags:
  - editor
  - lsp
---

## Fold setup

Pick one folding source for Markdown buffers. obsidian.nvim does not change your fold options unless you call `obsidian.folding.enable()`.

## Obsidian LSP folding

obsidian.nvim's in-process LSP server supports `textDocument/foldingRange` for markdown notes. It folds:

- YAML frontmatter
- Markdown heading sections

Use Neovim's LSP fold expression in a `FileType` autocmd or in `ftplugin/markdown.lua`:

```lua
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
```

If you only want to enable it after the Obsidian LSP client attaches:

```lua
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not (client and client.name == "obsidian-ls") then
      return
    end

    for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
      vim.wo[win][0].foldmethod = "expr"
      vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
      vim.wo[win][0].foldtext = "v:lua.vim.lsp.foldtext()"
    end
  end,
})
```

Helpful defaults:

```lua
vim.wo.foldlevel = 99 -- start unfolded
vim.wo.foldenable = true
```

### Custom fold text

You can wrap the LSP fold text if you want a custom display:

```lua
_G.obsidian_foldtext = function()
  local first = vim.trim(vim.fn.getline(vim.v.foldstart))
  local count = vim.v.foldend - vim.v.foldstart + 1
  return first .. " … " .. count .. " lines"
end

vim.wo.foldtext = "v:lua.obsidian_foldtext()"
```

## Tree-sitter folding

In a `FileType` autocmd, or in your `ftplugin/markdown.lua`:

```lua
vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo.foldmethod = "expr"
```

## Vim ftplugin folding

In your `init.lua` or anywhere before you open a file in vault.

```lua
vim.g.markdown_folding = 1
```

Same as:

```lua
vim.wo.foldexpr = "MarkdownFold()"
vim.wo.foldmethod = "expr"
vim.wo.foldtext = "MarkdownFoldText()"
```

## Org-style fold cycling

To use the outline actions, opt into Obsidian's outline fold expression instead of the LSP, Tree-sitter, or Vim Markdown fold expression. Add this to your config before opening a note:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function()
    require("obsidian.folding").enable()
  end,
})
```

`enable()` selects the fold expression for the current buffer in the current window and labels the YAML fold `Properties`. Your Neovim fold options still determine initial visibility. Set `foldlevelstart` to `99` to start unfolded by default, or use a per-note recipe below. Keep `foldminlines` at its default of `1` (or lower) if you want to collapse short sections.

Call these Lua actions or bind them to your own keys. Neither action has a default mapping.

| Action in `require("obsidian.actions")` | Effect |
| --- | --- |
| `fold_cycle()` | Cycle the heading at the cursor through **Folded → Children → Subtree**, or toggle **Properties**. |
| `fold_cycle_global()` | Cycle the current window through **Overview → Contents → Show all**. |

### Current heading or Properties

- **Folded:** collapse the whole section to its heading.
- **Children:** show the heading, its own body, and its direct child headings. Collapse the child sections.
- **Subtree:** show everything under the heading.

Start on a heading line, including the underline of a Setext heading. The action does nothing on body text or a heading with nothing to fold. It skips **Children** if none of the direct children can fold. A branch already showing **Children** advances to **Subtree**; any other partially open branch collapses. The action leaves other branches alone, including when you start from **Contents**.

On the collapsed **Properties** fold or anywhere inside open YAML frontmatter, `fold_cycle()` toggles that fold open or closed.

### Whole note

- **Overview (`overview`):** show top-level headings only.
- **Contents (`contents`):** show headings at every depth without their bodies.
- **Show all (`show_all`):** open all folds.

**Overview** and **Contents** leave introductory prose before the first heading visible and collapse YAML frontmatter. Blank lines between sections can remain visible. The first global action goes to **Overview**. After that, it advances from the last named view in this window for this buffer, even if you changed individual folds. If a view hides the cursor line, the cursor lands on the visible fold header.

### Differences from Org mode

[Org's visibility cycle](https://orgmode.org/manual/Global-and-local-cycling.html) can hide an entry body, a subtree, or a drawer independently. Markdown has headings, but no Org drawers or per-heading `VISIBILITY` properties. To reproduce **Contents**, the outline expression gives a heading separate native folds for its body and its subtree when both exist. Both folds can start on the same line, so native `za` can toggle the entry body before the entire branch. In a closed Setext fold, only the title line appears in the fold text; the underline is inside the fold.

`smart_action` still uses `za` on headings and in frontmatter when folding is configured. The outline actions do not add Org's table navigation, list or drawer cycling, numeric depth arguments, or automatic [startup directives](https://orgmode.org/manual/Initial-visibility.html).

### Recipe: startup view from frontmatter

Use `require("obsidian.folding").set_global("contents")` to apply a named view without cycling. The setter also updates the next global cycle step. To choose a view per note, add a custom YAML key:

```yaml
---
fold_startup: contents
---
```

The following config replaces the setup snippet above. It reads the key on the first display of each note in each window, so moving between windows does not undo later folding changes. The key is your convention: the plugin does not act on it without this config.

```lua
local folding = require "obsidian.folding"

local function apply_startup()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].obsidian_buffer then
    return
  end

  local seen = vim.w.obsidian_fold_startup or {}
  local key = tostring(buf)
  if seen[key] then
    return
  end
  seen[key] = true
  vim.w.obsidian_fold_startup = seen

  folding.enable()
  local note = require("obsidian.api").current_note(buf)
  local state = note and note.metadata and note.metadata.fold_startup
  if state == "overview" or state == "contents" or state == "show_all" then
    folding.set_global(state)
  end
end

local function on_enter()
  local win = vim.api.nvim_get_current_win()
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, apply_startup)
    end
  end)
end

vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = on_enter,
})
vim.api.nvim_create_autocmd("WinEnter", { callback = on_enter })
```

## See also

[[LSP]] · [[Keymaps]]
