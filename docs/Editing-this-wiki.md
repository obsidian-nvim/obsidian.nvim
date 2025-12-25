## Contribute to this wiki

- Fork the plugin repo
- Make changes in the `docs` folder
- Make a PR

## Modifying the content in this repo

- use `w!` to save the content
- or use the following snippet:

```lua
require("obsidian").setup {
  callback = {
    enter_note = function(note)
      if vim.b[note.bufnr].obsidian_help then
        vim.bo[note.bufnr].readonly = false
      end
    end,
  },
}
```

## To make this wiki work in both Github Wiki and Obsidian:

- To link files in this wiki, use media wiki links `[[file]]`
- To link anchors, use markdown links `[heading](#acnhor)`
