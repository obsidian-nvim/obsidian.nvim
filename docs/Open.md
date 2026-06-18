## Options

```lua
---@class obsidian.config.OpenOpts
---
---Opens the file with current line number
---@field use_advanced_uri? boolean
---
---Function to do the opening, default to vim.ui.open
---@field func? fun(uri: string, opts?: { fragment: string|?, location: string|?, params: table<string, string>|?, query: string|? })
---
---URI scheme whitelist, new values are appended to this list, and URIs with schemes in this list, will not be prompted to confirm opening
---@field schemes? string[]
open = {
  use_advanced_uri = false,
  func = vim.ui.open,
  schemes = { "https", "http", "file", "mailto" },
}
```

## PDF attachment links

For attachment links like `[[paper.pdf#page=3&selection=4,0,4,11]]`, `open.func`
receives the resolved attachment path as `uri` and the parsed params in `opts.params`.

Open PDFs to the linked page with zathura:

```lua
open = {
  func = function(uri, opts)
    if uri:match "%.pdf$" and opts and opts.params and opts.params.page then
      vim.system({ "zathura", "--page=" .. opts.params.page, uri }, { detach = true })
      return
    end

    vim.ui.open(uri)
  end,
}
```

Open PDFs with Obsidian's native PDF viewer, preserving `page` and `selection`:

```lua
open = {
  func = function(uri, opts)
    if uri:match "^obsidian://" then
      vim.ui.open(uri)
      return
    end

    if uri:match "%.pdf$" then
      local path = require("obsidian.path").new(uri):vault_relative_path()
      if path then
        local vault = vim.uri_encode(vim.fs.basename(tostring(Obsidian.workspace.root)))
        local file = vim.uri_encode(path)
        local fragment = opts and opts.fragment and ("#" .. opts.fragment) or ""
        vim.ui.open(("obsidian://open?vault=%s&file=%s%s"):format(vault, file, fragment))
        return
      end
    end

    vim.ui.open(uri)
  end,
}
```
