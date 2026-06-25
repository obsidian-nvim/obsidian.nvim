See [LSP code actions](LSP.md#code-actions) for actions exposed via the LSP interface.

## Action-first picker model

Pickers are now thin selection UIs. Prefer choosing the action first, then selecting an item if needed:

- use `Obsidian insert_link` to open a note picker that inserts the selected note as a link;
- use `Obsidian quick_switch` to open a note picker that opens the selected note;
- use `Obsidian search_tags`, `Obsidian insert_tag`, or `Obsidian add_tag` for tag workflows.

Legacy query mappings are only kept for creating a note from typed picker text (`picker.note_mappings.new`, default `<C-x>`) and only for `telescope.nvim` and `fzf-lua`. Selection mappings such as `picker.note_mappings.insert_link` and `picker.tag_mappings` were removed; use the action commands above instead.

| name                 | mode     | description                            | arguments            |
| -------------------- | -------- | -------------------------------------- | -------------------- |
| `follow_link`        | `n`      | Open the link under the cursor.        | `link`               |
| `nav_link`           | `n`      | Navigate to next/previous link.        | `direction`          |
| `smart_action`       | `n`      | Context-aware action on the cursor.    |                      |
| `new`                | `n`      | Create a new note.                     | `id`                 |
| `new_from_template`  | `n`      | Create a new note from a template.     | `id`, `template`     |
| `unique_note`        | `n`      | Create a unique note.                  | `timestamp`          |
| `unique_link`        | `n`      | Create and insert a unique note link.  | `timestamp`          |
| `add_property`       | `n`      | Add frontmatter property.              |                      |
| `insert_template`    | `n`      | Insert a template at cursor.           | `name`               |
| `rename`             | `n`      | Rename current note.                   | `name`               |
| `move_note`          | `n`      | Move current note to another folder.   |                      |
| `merge_note`         | `n`      | Merge current note into another note.  | `dst_note`           |
| `start_presentation` | `n`      | Start slide presentation.              | `buf`                |
| `workspace_symbol`   | `n`      | Search notes, aliases, and headings.   | `query`              |
| `toggle_checkbox`    | `n`, `v` | Toggle (cycle) checkbox state.         | `start_lnum`, `end_lnum` |
| `set_checkbox`       | `n`, `v` | Set to specific checkbox state.        | `state`              |
| `link`               | `v`      | Link selection to an existing note.    |                      |
| `link_new`           | `v`      | Create a new note and link selection.  | `title`              |
| `extract_note`       | `v`      | Move selection to a new note.          | `title`              |
