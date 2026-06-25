<!-- TODO: list all the things that you need to migrate -->

1. Follow any warning that pops up when you enter neovim. We group config options more logically to have better docs and improve feature accessibility.
2. All the functions in the `callback` section, the first argument `client` is removed, e.g. `opts.callback.enter_note(client, note)` -> `opts.callback.enter_note(note)`.
3. New notes created will not have a default H1 heading. To restore old behavior, use [[Note#default-note-template]] to insert title as H1 heading.
4. Completion will only be triggered by `[[` for both markdown and wiki links, like obsidian app, it will be less intrusive for typing.
5. Bare urls, fileurls, mailtourls will no longer work, always enclose them in markdown list like `[my email](mailto:example@gmail.com)`
6. Picker selection mappings were removed. `picker.note_mappings.insert_link` and `picker.tag_mappings` no longer run actions from inside a picker. Use action-first commands instead: `Obsidian insert_link`, `Obsidian quick_switch`, `Obsidian search_tags`, `Obsidian insert_tag`, and `Obsidian add_tag`.
7. Picker query mappings are legacy and limited to creating a note from typed picker text. `picker.note_mappings.new` (default `<C-x>`) is supported only by `telescope.nvim` and `fzf-lua`; other pickers should use `Obsidian new` / `Obsidian link_new`.

## Planned breaking changes

1. `legacy commands` will be removed, along with `ObsidianQuickSwitch` style commands.
2. [UI module will be removed in the future, and it is recommend to use dedicated markdown render plugins](https://github.com/orgs/obsidian-nvim/discussions/491)
