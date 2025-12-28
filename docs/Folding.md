## Fold setup

This plugin will not override your fold options. There's two recommended ways to setup folding:

### Tree-sitter folding

In a `FileType` autocmd, or in your `ftplugin/markdown.lua`

```lua
vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo.foldmethod = "expr"
```

### Vim ftplugin folding

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

**Feature to be implemented**
