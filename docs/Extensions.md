**This is for developers**

Example plugin of integrating: [obsidian-markmap.nvim](https://github.com/obsidian-nvim/obsidian-markmap.nvim)

## Organize your plugin like

So that your command shows up in the command completion/menu.

```bash
├── LICENSE
├── lua
│   └── obsidian
│       └── commands
│           └── map.lua # command name your want to add, should be minimal, requires the logic from map module
│   └── map
│       └── init.lua # actual logic
├── plugin
│   └── map.lua # register your command here
└── README.md
```

```lua
return {
   "obsidian-nvim/obsidian.nvim",
   dependencies = {
      "your/plugin", -- makes sure your plugin loads first
   },
}
```

## Register your command

`your-plugin-dir/plugin/map.lua`:

```lua
require("obsidian").register_command("map", { nargs = 0 })
```

See [commands/init.lua](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/lua/obsidian/commands/init.lua) for usage.
