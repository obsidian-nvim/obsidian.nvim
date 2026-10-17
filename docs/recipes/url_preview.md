---
title: "Defuddle URL preview recipe"
tags:
  - developers
  - recipes
---

# Optional Defuddle URL previews

The built-in URL preview does not contact the network. This opt-in `resolvers.url_preview` recipe fetches page content through Defuddle and returns preview lines.

## Disclosure and safety

- Each preview sends the full HTTP(S) URL to `https://defuddle.md/`. That service can observe the URL, including its path and query string.
- Do not use this for URLs containing credentials, access tokens, private document IDs, or other sensitive query parameters.
- The resolver only accepts `http://` and `https://` targets. It does not launch a browser or other external application.
- `curl` is required. Requests have an 8-second timeout and a 1 MiB response limit. Results are cached in memory (up to 32 URLs); concurrent requests for the same URL share one fetch.

## Configuration

```lua
local cache = {}
local cache_order = {}
local in_flight = {}
local max_bytes = 1024 * 1024
local max_cache_entries = 32

local function finish(url, callbacks, result, err)
  in_flight[url] = nil
  if result then
    cache[url] = result
    cache_order[#cache_order + 1] = url
    while #cache_order > max_cache_entries do
      local expired = table.remove(cache_order, 1)
      cache[expired] = nil
    end
  end
  for _, done in ipairs(callbacks) do
    done(result, err)
  end
end

require("obsidian").setup {
  resolvers = {
    url_preview = function(ctx, done)
      if type(ctx.url) ~= "string" or not ctx.url:match("^https?://") then
        done(nil, "Defuddle previews support HTTP(S) URLs only")
        return
      end
      if cache[ctx.url] then
        done(cache[ctx.url])
        return
      end
      if in_flight[ctx.url] then
        in_flight[ctx.url][#in_flight[ctx.url] + 1] = done
        return
      end

      local callbacks = { done }
      in_flight[ctx.url] = callbacks
      vim.system({
        "curl",
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--max-time",
        "8",
        "--max-filesize",
        tostring(max_bytes),
        "--",
        "https://defuddle.md/" .. ctx.url,
      }, { text = true }, vim.schedule_wrap(function(out)
        if out.code ~= 0 or type(out.stdout) ~= "string" or out.stdout == "" then
          finish(ctx.url, callbacks, nil, "Defuddle URL preview request failed")
          return
        end
        if #out.stdout > max_bytes then
          finish(ctx.url, callbacks, nil, "Defuddle URL preview exceeded the size limit")
          return
        end

        local result = {
          lines = vim.split(out.stdout, "\n", { plain = true }),
          filetype = "markdown",
        }
        finish(ctx.url, callbacks, result)
      end))
    end,
  },
}
```

The cache and in-flight map live for the Neovim process lifetime. Restart Neovim to clear them. Resolver results are content only; do not allocate or return picker buffers. See [[Resolvers#URL preview resolver]] for the contract and default behavior.
