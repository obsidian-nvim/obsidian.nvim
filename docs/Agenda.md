# Agenda

Open an orgmode-like agenda view for markdown checkbox tasks.

```vim
:Obsidian agenda
:Obsidian agenda week
:Obsidian agenda day 2026-05-29
:Obsidian agenda month
:Obsidian agenda year
:Obsidian agenda todo
```

By default tasks are read from `agenda.md` in the vault root.

```md
- [ ] Pay rent @due(2026-06-01) #home
- [ ] Draft release notes @scheduled(2026-05-29) [#A]
- [ ] Call Sam @2026-05-30
- [x] Submit taxes @due(2026-04-15) @done(2026-04-14)
```

Supported markers:

- `@YYYY-MM-DD`: plain agenda date
- `@due(YYYY-MM-DD)`: deadline
- `@scheduled(YYYY-MM-DD)`: scheduled date
- `@done(YYYY-MM-DD)`: completion date
- `[#A]`, `[#B]`, `[#C]`: priority
- `#tag`: tag

Default views hide completed tasks and show undated tasks in day/week/todo views.

## Config

```lua
require("obsidian").setup {
  date = {
    -- 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    start_of_week = 1,
  },
  agenda = {
    file = "agenda.md",
    default_view = "week",
  },
}
```

## Custom async source

Replace `agenda.get_items` to read tasks from daily notes or any other source.

```lua
require("obsidian").setup {
  agenda = {
    get_items = function(ctx, done)
      vim.schedule(function()
        local items = {}
        vim.list_extend(items, ctx.parse_markdown_file(ctx.default_file()))
        done(items)
      end)
    end,
  },
}
```

Each item may provide custom actions:

```lua
{
  title = "Review notes",
  status = "todo",
  actions = {
    open = function(item) end,
    toggle = function(item) end,
  },
}
```
