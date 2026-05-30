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

## Daily notes as agenda source

This example extracts all checkbox tasks from every daily note and uses the daily note filename as the task date. It assumes daily notes are named with `daily_notes.date_format`, for example `YYYY-MM-DD.md`.

```lua
local Path = require "obsidian.path"
local util = require "obsidian.util"

require("obsidian").setup {
  agenda = {
    get_items = function(ctx, done)
      local daily_dir = Path.new(Obsidian.dir)

      if Obsidian.opts.daily_notes.folder then
        daily_dir = daily_dir / Obsidian.opts.daily_notes.folder
      elseif Obsidian.opts.notes_subdir then
        daily_dir = daily_dir / Obsidian.opts.notes_subdir
      end

      vim.system({
        "rg",
        "--files",
        "-g",
        "*.md",
        tostring(daily_dir),
      }, { text = true }, function(result)
        if result.code ~= 0 and result.stdout == "" then
          done({}, result.stderr)
          return
        end

        local items = {}

        for file in vim.gsplit(result.stdout or "", "\n", { trimempty = true }) do
          local path = Path.new(file)
          local date = util.parse_date(path.stem, Obsidian.opts.daily_notes.date_format)

          if date then
            local timestamp = os.time {
              year = date.year,
              month = date.month,
              day = date.day,
              hour = 12,
              min = 0,
              sec = 0,
            }

            for _, item in ipairs(ctx.parse_markdown_file(path)) do
              -- Explicit agenda markers win. Otherwise inherit date from the daily note.
              item.date = item.date or item.scheduled or item.due or timestamp
              item.source = "daily"
              items[#items + 1] = item
            end
          end
        end

        done(items)
      end)
    end,
  },
}
```

For a daily note like:

```md
# 2026-05-30

- [ ] Call Sam
- [ ] Buy groceries
- [x] Done task
- [ ] Explicit deadline @due(2026-06-01)
```

The first two tasks inherit `2026-05-30`; the deadline task keeps its explicit deadline.
