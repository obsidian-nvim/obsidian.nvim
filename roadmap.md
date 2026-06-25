# Kanban roadmap

## MVP shipped

- Parse Obsidian Kanban-compatible markdown boards (`##` columns, `- [ ]` / `- [x]` cards).
- Serve a local browser UI from `lua/obsidian/web/server.lua`.
- `:Obsidian kanban` opens the current markdown note as a board.
- Drag cards between columns or reorder within a column.
- Add cards, add columns, rename columns, and toggle done state.
- Preserve frontmatter, non-board preamble, column leading text, and multi-line card bodies during writes.

## Next

- Full obsidian-kanban settings block support (`%% kanban:settings`).
- Card editing/deletion, archive behavior, and date/tag helpers.
- Better multi-line card editing with markdown preview.
- Live updates via server-sent events when the note changes in Neovim.
- Column collapse, WIP limits, and saved UI state.
- Tests for HTTP endpoints and browser actions.
