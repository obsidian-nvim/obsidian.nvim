## Plugin Completion

This plugin provide plugin-agnostic completion via in-process LSP, you only need to make sure you are triggering LSP completions in markdown buffers.

For blink.cmp, if you have a dedicated `per_filetype` config for markdown, lsp completion will not attach, use:

```lua

require("blink.cmp").setup {
  sources = {
    -- NOTE: no need if you don't have custom markdown stuff
    per_filetype = {
      markdown = {
        "lsp", -- NOTE: explicitly enable lsp
        -- inherit_defaults = true, -- NOTE: if your defaults include lsp
        "dictionary",
      },
    },
  },
}
```

## Neovim Native Completion

To use completions without completion plugin, put this anywhere in your config before an obsidian buffer loads:

```lua
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local buf = ev.buf
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "obsidian-ls" then
      vim.bo[buf].completeopt = "menuone,noselect,fuzzy,nosort" -- noselect to make sure no accidentally accept and create new notes, others are not strictly necessary, adjust to your taste, see `:h completeopt'
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end
  end,
})
```
