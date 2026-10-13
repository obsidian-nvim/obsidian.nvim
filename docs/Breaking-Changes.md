---
title: "Breaking Changes"
tags:
  - migration
  - reference
---

<!-- TODO: list all the things that you need to migrate -->

1. Follow any warning that pops up when you enter neovim. We group config options more logically to have better docs and improve feature accessibility.
2. All the functions in the `callback` section, the first argument `client` is removed, e.g. `opts.callback.enter_note(client, note)` -> `opts.callback.enter_note(note)`.
3. New notes created will not have a default H1 heading. To restore old behavior, use [[Note#default-note-template]] to insert title as H1 heading.
4. Completion will only be triggered by `[[` for both markdown and wiki links, like obsidian app, it will be less intrusive for typing.
5. Bare urls, fileurls, mailtourls will no longer work, always enclose them in markdown list like `[my email](mailto:example@gmail.com)`

## Daily notes command redesign

- Use `:Obsidian daily [DATE]` to open one note. Bare `daily` opens today; `tomorrow` and `yesterday` respect `daily_notes.workdays_only`. Numeric offsets and formatted dates always refer to calendar days.
- Use `:Obsidian dailies [OFFSET [OFFSET]]` for the picker. Bare `dailies` still lists five days ago through today. One offset now spans between that day and today (so `dailies 2` shows today through two days ahead rather than starting five days ago).
- `:Obsidian today`, `:Obsidian tomorrow`, and `:Obsidian yesterday` are hidden from the subcommand menu and completion but remain callable, as do `:ObsidianToday`, `:ObsidianTomorrow`, and `:ObsidianYesterday`. Their previous behavior is preserved until removal in 4.0.
- Rename custom `opts.resolvers.date` to `opts.resolvers.date_select`. The old name remains a deprecated selection-only alias until 4.0. To parse typed dates, implement `opts.resolvers.date_parse`; its `ctx.fallback(ctx, done)` calls the built-in parser. These names follow the `primitive_verb` convention; updating other resolvers is deferred to a separate change. See [[Resolvers#date-selection-and-parsing]].

## Planned breaking changes

1. `legacy commands` will be removed in 4.0, along with `ObsidianQuickSwitch` style commands and the older daily-note command aliases.
2. [UI module will be removed in the future, and it is recommend to use dedicated markdown render plugins](https://github.com/orgs/obsidian-nvim/discussions/491)
