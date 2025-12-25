[Options](#Options)

## Usage

To insert a template in the current note, run the command `:Obsidian template`. This will open a list of available templates in your templates folder with your preferred picker. Select a template and hit `<CR>` to insert.

To create a new note from a template, run the command `:Obsidian new_from_template`. This will prompt you for an optional path for the new note and will open a list of available templates in your templates folder with your preferred picker. Select a template and hit `<CR>` to create the new note with the selected template.

Substitutions for `{{id}}`, `{{title}}`, `{{path}}`, `{{date}}`, and `{{time}}` are supported out-of-the-box.
For example, with the following configuration

```lua
require("obsidian").setup({
   -- other fields ...

   templates = {
      folder = "my-templates-folder",
      date_format = "%Y-%m-%d-%a",
      time_format = "%H:%M",
   },
})
```

and the file `~/my-vault/my-templates-folder/note template.md`:

```markdown
# {{title}}

Date created: {{date}}
```

Creating the note `Configuring Neovim.md` and executing `:Obsidian template` will insert the following above the cursor position.

```markdown
# Configuring Neovim

Date created: 2023-03-01-Wed
```

## Substitutions

You can also define custom template substitutions with the configuration field `templates.substitutions`. For example, to automatically substitute the template variable `{{yesterday}}` when inserting a template, you could add this to your config:

```lua
require("obsidian").setup({
   -- other fields ...
   templates = {
      substitutions = {
         yesterday = function()
            return os.date("%Y-%m-%d", os.time() - 86400)
         end,
      },
   },
})
```

Substitution functions are passed `obsidian.TemplateContext` objects with details about _which_ template is being used. For example, to return different values from different templates:

```lua
--- NOTE: For weekly templates this means "seven days ago", otherwise it means "one day ago".
yesterday = function(ctx)
   if vim.endswith(ctx.template_name, "Weekly Note Template.md") then
      return os.date("%Y-%m-%d", os.time() - 86400 * 7)
   end
   -- Fallback
   return os.date("%Y-%m-%d", os.time() - 86400)
end
```

### Context Types

```lua
---@alias obsidian.TemplateContext obsidian.InsertTemplateContext | obsidian.CloneTemplateContext
---The table passed to user substitution functions. Use `ctx.type` to distinguish between the different kinds.

---@class obsidian.InsertTemplateContext
---The table passed to user substitution functions when inserting templates into a buffer.
---
---@field type "insert_template"
---@field template_name string|obsidian.Path The name or path of the template being used.
---@field template_opts obsidian.config.TemplateOpts The template options being used.
---@field templates_dir obsidian.Path The folder containing the template file.
---@field location [number, number, number, number] `{ buf, win, row, col }` location from which the request was made.
---@field partial_note? obsidian.Note An optional note with fields to copy from.

---@class obsidian.CloneTemplateContext
---The table passed to user substitution functions when cloning template files to create new notes.
---
---@field type "clone_template"
---@field template_name string|obsidian.Path The name or path of the template being used.
---@field template_opts obsidian.config.TemplateOpts The template options being used.
---@field templates_dir obsidian.Path The folder containing the template file.
---@field destination_path obsidian.Path The path the cloned template will be written to.
---@field partial_note obsidian.Note The note being written.
```

## Customizations

You can specify _per-template_ behavior using the `templates.customizations` configuration field. You may want to do this if you want to:

**1. Control which directory a new note is placed in based on the template you used to create it**

You might want all of your notes created using your `meeting.md` template to go to `{vault_root}/jobs/my-job/meetings/`

```lua
require("obsidian").setup({
   -- other fields ...
   templates = {
      customizations = {
         meeting = {
            notes_subdir = "jobs/my-job/meetings",
         },
      },
   },
})
```

**2. Control the ID generated for notes based on the template you used to create it**

For example, rather than a default, Zettelkasten-style note for prominent people you want to study, you could opt for a simpler ID:

```lua
biography = {
   -- This function currently only receives the note title as an input
   note_id_func = function(title)
      if title == nil then
         return nil
      end

      local name = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
      return name -- "Hulk Hogan" → "hulk-hogan"
   end,
}
```

> [!IMPORTANT]
> The name of the template file **_must match_** the name specified in your configuration
>
> | Template            | Customization        |
> | ------------------- | -------------------- |
> | book.md             | book                 |
> | personal-diaries.md | ["personal-diaries"] |
> | big books.md        | ["big books"]        |

### Full Type Annotation

```lua
---@class obsidian.config.CustomTemplateOpts
---
---@field notes_subdir? string
---@field note_id_func? (fun(title: string|?): string)
```

## Options

```lua
---@class obsidian.config.TemplateOpts
---
---@field folder string|obsidian.Path|?
---@field date_format string|?
---@field time_format string|?
--- A map for custom variables, the key should be the variable and the value a function.
--- Functions are called with obsidian.TemplateContext objects as their sole parameter.
--- See: https://github.com/obsidian-nvim/obsidian.nvim/wiki/Template#substitutions
---@field substitutions table<string, (fun(ctx: obsidian.TemplateContext):string)|(fun(): string)|string>|?
---@field customizations table<string, obsidian.config.CustomTemplateOpts>|?
```
