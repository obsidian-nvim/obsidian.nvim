<!-- TODO: list all the things that you need to migrate -->

1. Follow any warning that pops up when you enter neovim. We group config options more logically to have better docs and improve feature accessibility.
2. All the functions in the `callback` section, the first argument `client` is removed, e.g. `opts.callback.enter_note(client, note)` -> `opts.callback.enter_note(note)`.
3. New notes created will not have a default H1 heading. (restoring the old behavior needs another WIP refactor #575)
4. `opts.wiki_link_func` -> `opts.link.wiki` and no longer accept a string preset, for customization, see [[Link#customizing-links]]
5. completion will only be triggered by `[[` for both markdown and wiki links, like obsidian app, it will be less intrusive for typing.
6. Bare urls, fileurls, mailtourls will no longer work, always enclose them in markdown list like `[my email](mailto:example@gmail.com)`

## Planned breaking changes

1. `legacy commands` will be removed, along with `ObsidianQuickSwitch` style commands.
2. [UI module will be removed in the future, and it is recommend to use dedicated markdown render plugins](https://github.com/orgs/obsidian-nvim/discussions/491)
