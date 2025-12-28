## Vault-based workspaces

For most Obsidian users, each workspace you configure in your obsidian.nvim config should correspond to a unique Obsidian vault, in which case the `path` of each workspace should be set to the corresponding vault root path.

For example, suppose you have an Obsidian vault at `~/vaults/personal`, then the `workspaces` field in your config would look like this:

```lua
config = {
   workspaces = {
      {
         name = "personal",
         path = "~/vaults/personal",
      },
   },
}
```

However obsidian.nvim's concept of workspaces is a little more general than that of vaults, since it's also valid to configure a workspace that doesn't correspond to a vault, or to configure multiple workspaces for a single vault. The latter case can be useful if you want to segment a single vault into multiple directories with different settings applied to each directory. For example:

```lua
config = {
   workspaces = {
      {
         name = "project-1",
         path = "~/vaults/personal/project-1",
         -- `strict=true` here tells obsidian to use the `path` as the workspace/vault root,
         -- even though the actual Obsidian vault root may be `~/vaults/personal/`.
         strict = true,
         overrides = {
            -- ...
         },
      },
      {
         name = "project-2",
         path = "~/vaults/personal/project-2",
         strict = true,
         overrides = {
            -- ...
         },
      },
   },
}
```

## Dynamic workspaces

obsidian.nvim also supports "dynamic" workspaces. These are simply workspaces where the `path` is set to a Lua function (that returns a path) instead of a hard-coded path. This can be useful in several scenarios, such as when you want a workspace whose `path` is always set to the parent directory of the current buffer:

```lua
config = {
   workspaces = {
      {
         name = "buf-parent",
         path = function()
            return assert(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
         end,
      },
   },
}
```

Dynamic workspaces are also useful when you want to use a subset of this plugin's functionality on markdown files outside of your "fixed" vaults.

## Use outside of workspace

It's possible to configure obsidian.nvim to work on individual markdown files outside of a regular workspace / Obsidian vault by configuring a "dynamic" workspace. To do so you just need to add a special workspace with a function for the `path` field (instead of a string), which should return a _parent_ directory of the current buffer. This tells obsidian.nvim to use that directory as the workspace `path` and `root` (vault root) when the buffer is not located inside another fixed workspace.

For example, to extend the configuration above this way:

```diff
{
  workspaces = {
     {
       name = "personal",
       path = "~/vaults/personal",
     },
     ...
+    {
+      name = "no-vault",
+      path = function()
+        -- alternatively use the CWD:
+        -- return assert(vim.fn.getcwd())
+        return assert(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
+      end,
+      overrides = {
+        notes_subdir = vim.NIL,  -- have to use 'vim.NIL' instead of 'nil'
+        new_notes_location = "current_dir",
+        templates = {
+          folder = vim.NIL,
+        },
+        disable_frontmatter = true,
+      },
+    },
+  },
   ...
}
```

With this configuration, anytime you enter a markdown buffer outside of "~/vaults/personal" (or whatever your configured fixed vaults are), obsidian.nvim will switch to the dynamic workspace with the path / root set to the parent directory of the buffer.

Please note that in order to avoid unexpected behavior (like a new directory being created for `notes_subdir`) it's important to carefully set the workspace `overrides` options.
And keep in mind that to reset a configuration option to `nil` you'll have to use `vim.NIL` there instead of the builtin Lua `nil` due to the way Lua tables work.

