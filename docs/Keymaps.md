## Create new mapping

See: [[Autocmds]]

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function(ev)
    vim.keymap.set("n", "<leader>ch", "<cmd>Obsidian toggle_checkbox<cr>", {
      buffer = true,
      desc = "Toggle checkbox",
    })
  end,
})
```

Or with the callback module:

```lua
require("obsidian").setup {
  callbacks = {
    enter_note = function(note)
      vim.keymap.set("n", "<leader>ch", "<cmd>Obsidian toggle_checkbox<cr>", {
        buffer = true,
        desc = "Toggle checkbox",
      })
    end,
  },
}
```

## Remap default mapping

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function(ev)
    -- remove the default mappings
    vim.keymap.del("n", "<CR>", { buffer = true })
    vim.keymap.del("n", "]o", { buffer = true })
    vim.keymap.del("n", "[o", { buffer = true })

    -- add your own
    vim.keymap.set("n", "<leader><CR>", require("obsidian.api").smart_action, { buffer = true })
    vim.keymap.del("n", "]l", { buffer = true })
    vim.keymap.del("n", "[l", { buffer = true })
  end,
})
```

Or with the callback module like above.

## Action functions

The plugin provides the following remappable functions:
<!-- TODO: auto generate from inline docs? -->
<!-- TODO: move to Actions.md -->

- `smart_action`
  - If cursor is on a link, follow the link
  - If cursor is on a tag, show all notes with that tag in a picker
  - If cursor is on a checkbox, toggle the checkbox
  - If cursor is on a heading, cycle the fold of that heading
- `nav_link ["next"|"prev"]`
  - Will navigate cursor to next valid link in the buffer
- `set_checkbox [state]`
  - If cursor is on a checkbox, set the state to the parameter given
  - If cursor is on a checkbox and no parameter was given, set the state to the next input
  - Note: Either given state or next input will have to be a valid choice in `Obsidian.ui.checkboxes` (if you didn't specify any you can check the [README configuration](https://github.com/obsidian-nvim/obsidian.nvim?tab=readme-ov-file#%EF%B8%8F-configuration) for the default list of them)
- `toggle_checkbox`
- `link`
- `link_new`
- `extract_note`
- `new_from_template`

For their implementation, see [obsidian.nvim/lua/obsidian/action.lua at main · obsidian-nvim/obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/lua/obsidian/action.lua)

Example with remapping `nav_link`:

```lua
require("obsidian").setup {
  callbacks = {
    enter_note = function(note)
      local actions = require "obsidian.actions"
      vim.keymap.set("n", "<leader>;", actions.add_property, { buffer = true, desc = "Add frontmatter property" })
      vim.keymap.set("n", "<Tab>", function()
        actions.nav_link "next"
      end, { buffer = true, desc = "Go to next link" })
      vim.keymap.set("n", "<S-Tab>", function()
        actions.nav_link "prev"
      end, { buffer = true, desc = "Go to previous link" })
    end,
  },
}
```
