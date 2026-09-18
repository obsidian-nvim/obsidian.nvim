## Fold setup

This plugin will not override your fold options. Pick one folding source and set it for markdown buffers.

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

## Fold cycling

When folding is configured, the `smart_action` action cycles the fold under the cursor when the cursor is on a heading or in frontmatter.
