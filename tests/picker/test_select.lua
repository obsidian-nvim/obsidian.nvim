local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local function with_module(name, module, fn)
  local original = package.loaded[name]
  package.loaded[name] = module
  local ok, err = pcall(fn)
  package.loaded[name] = original
  if not ok then
    error(err)
  end
end

local function with_modules(modules, fn)
  local originals = {}
  for name, module in pairs(modules) do
    originals[name] = package.loaded[name] or false
    package.loaded[name] = module
  end
  local ok, err = pcall(fn)
  for name in pairs(modules) do
    package.loaded[name] = originals[name] or nil
  end
  if not ok then
    error(err)
  end
end

local function with_obsidian(obsidian, fn)
  local original = Obsidian
  Obsidian = obsidian
  local ok, err = pcall(fn)
  Obsidian = original
  if not ok then
    error(err)
  end
end

T["mini select returns all marked items when multiple selections are allowed"] = function()
  local choices

  with_module("mini.pick", {
    start = function(opts)
      eq("Pick", opts.source.name)
      eq("one", opts.source.items[1].obsidian_item)
      eq("two", opts.source.items[2].obsidian_item)
      opts.source.choose_marked { opts.source.items[1], opts.source.items[2] }
      return opts.source.items[2]
    end,
  }, function()
    require("obsidian.picker.mini").select(
      { "one", "two" },
      { prompt = "Pick", allow_multiple = true },
      function(selected)
        choices = selected
      end
    )
  end)

  eq({ "one", "two" }, choices)
end

T["mini select applies custom formatting to string values"] = function()
  with_module("mini.pick", {
    start = function(opts)
      eq("display:one", opts.source.items[1].text)
    end,
  }, function()
    require("obsidian.picker.mini").select({ "one" }, {
      format_item = function(value)
        return "display:" .. value
      end,
    })
  end)
end

T["fzf select explicitly enables multiple selections and returns all choices"] = function()
  local choices

  with_modules({
    ["fzf-lua.previewer.builtin"] = {},
    ["fzf-lua"] = {
      fzf_exec = function(entries, opts)
        eq({ "1\tone", "2\ttwo" }, entries)
        eq({
          ["--delimiter"] = "\t",
          ["--with-nth"] = "2..",
          ["--multi"] = true,
          ["--no-multi"] = false,
        }, opts.fzf_opts)
        opts.actions.default(entries)
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ "one", "two" }, { allow_multiple = true }, function(selected)
      choices = selected
    end)
  end)

  eq({ "one", "two" }, choices)
end

T["fzf select applies custom formatting to string values"] = function()
  with_modules({
    ["fzf-lua.previewer.builtin"] = {},
    ["fzf-lua"] = {
      fzf_exec = function(entries)
        eq({ "1\tdisplay:one" }, entries)
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ "one" }, {
      format_item = function(value)
        return "display:" .. value
      end,
    })
  end)
end

T["fzf select explicitly disables unsupported multiple selections"] = function()
  with_modules({
    ["fzf-lua.previewer.builtin"] = {},
    ["fzf-lua"] = {
      fzf_exec = function(_, opts)
        eq({
          ["--delimiter"] = "\t",
          ["--with-nth"] = "2..",
          ["--multi"] = false,
          ["--no-multi"] = true,
        }, opts.fzf_opts)
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ "one", "two" }, {}, function() end)
  end)
end

T["fzf select enables multiple selections for mappings that accept them"] = function()
  local mapped
  with_modules({
    ["fzf-lua.previewer.builtin"] = {},
    ["fzf-lua"] = {
      fzf_exec = function(entries, opts)
        eq({
          ["--delimiter"] = "\t",
          ["--with-nth"] = "2..",
          ["--multi"] = true,
          ["--no-multi"] = false,
        }, opts.fzf_opts)
        opts.actions["ctrl-t"](entries)
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ "one", "two" }, {
      selection_mappings = {
        ["<C-t>"] = {
          desc = "test",
          allow_multiple = true,
          callback = function(...)
            mapped = { ... }
          end,
        },
      },
    }, function() end)
  end)
  eq({ "one", "two" }, mapped)
end

T["fzf select preserves identity for duplicate display labels"] = function()
  local first = { id = 1 }
  local second = { id = 2 }
  local choices
  local previewed = {}

  with_modules({
    ["fzf-lua.previewer.builtin"] = {
      buffer_or_file = {
        extend = function()
          return {}
        end,
      },
    },
    ["fzf-lua"] = {
      fzf_exec = function(entries, opts)
        eq({ "1\tduplicate", "2\tduplicate" }, entries)
        opts.previewer.parse_entry(nil, entries[1])
        opts.previewer.parse_entry(nil, entries[2])
        opts.actions.default { entries[1] }
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ first, second }, {
      format_item = function()
        return "duplicate"
      end,
      preview_item = function(value)
        previewed[#previewed + 1] = value
        return { buf = vim.api.nvim_create_buf(false, true) }
      end,
    }, function(selected)
      choices = selected
    end)
  end)

  eq({ first, second }, previewed)
  eq({ first }, choices)
end

T["fzf select does not infer previews from value shape"] = function()
  local value = { filename = "/vault/note.md" }
  with_modules({
    ["fzf-lua.previewer.builtin"] = {
      buffer_or_file = {
        extend = function()
          error "unexpected inferred preview"
        end,
      },
    },
    ["fzf-lua"] = {
      fzf_exec = function(_, opts)
        eq(nil, opts.previewer)
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ value }, {
      format_item = function()
        return "note"
      end,
    })
  end)
end

T["snacks select applies custom formatting to string values"] = function()
  with_module("snacks.picker", {
    pick = function(opts)
      eq("display:one", opts.items[1].text)
      eq("one", opts.items[1].obsidian_item)
    end,
  }, function()
    require("obsidian.picker.snacks").select({ "one" }, {
      format_item = function(value)
        return "display:" .. value
      end,
    })
  end)
end

T["snacks select preserves opaque values for mappings"] = function()
  local value = { filename = "/vault/note.md" }
  local mapped
  with_module("snacks.picker", {
    pick = function(opts)
      eq(nil, opts.items[1].file)
      eq(false, opts.layout.preview)
      opts.actions.map({
        close = function() end,
      }, opts.items[1])
    end,
  }, function()
    require("obsidian.picker.snacks").select({ value }, {
      format_item = function()
        return "note"
      end,
      selection_mappings = {
        ["<C-l>"] = {
          desc = "map",
          callback = function(selected)
            mapped = selected
          end,
        },
      },
    })
    vim.wait(1000, function()
      return mapped ~= nil
    end)
  end)
  eq(value, mapped)
end

T["telescope select applies custom formatting to string values"] = function()
  with_modules({
    ["telescope.pickers"] = {
      new = function(_, opts)
        local entry = opts.finder.entry_maker(opts.finder.results[1])
        eq("display:one", entry.display())
        eq("one", entry.obsidian_item)
        return { find = function() end }
      end,
    },
    ["telescope.finders"] = {
      new_table = function(opts)
        return opts
      end,
    },
    ["telescope.config"] = {
      values = {
        generic_sorter = function()
          return {}
        end,
      },
    },
  }, function()
    require("obsidian.picker.telescope").select({ "one" }, {
      format_item = function(value)
        return "display:" .. value
      end,
    })
  end)
end

T["telescope select does not infer fields or previews from value shape"] = function()
  local value = { filename = "/vault/note.md" }
  with_modules({
    ["telescope.pickers"] = {
      new = function(_, opts)
        local entry = opts.finder.entry_maker(opts.finder.results[1])
        eq(value, entry.value)
        eq(nil, entry.filename)
        eq(nil, opts.previewer)
        return { find = function() end }
      end,
    },
    ["telescope.finders"] = {
      new_table = function(opts)
        return opts
      end,
    },
    ["telescope.config"] = {
      values = {
        generic_sorter = function()
          return {}
        end,
        grep_previewer = function()
          error "unexpected inferred preview"
        end,
      },
    },
  }, function()
    require("obsidian.picker.telescope").select({ value }, {
      format_item = function()
        return "note"
      end,
    })
  end)
end

T["fzf grep confirmation retains entries and mappings receive paths"] = function()
  local mapped = {}
  local grepped = {}

  with_obsidian({ opts = { search = { sort_by = false, sort_reversed = false } } }, function()
    with_modules({
      ["fzf-lua.path"] = {
        entry_to_file = function(entry)
          if entry == "one" then
            return { path = "/vault/one.md", line = 2, col = 3 }
          else
            return { path = "/vault/two.md", line = 0, col = 0 }
          end
        end,
      },
      ["fzf-lua"] = {
        grep = function(opts)
          opts.actions.default({ "one", "two" }, {})
          opts.actions["ctrl-l"]({ "one", "two" }, {})
        end,
      },
    }, function()
      local fzf = require "obsidian.picker.fzf"
      fzf.grep {
        dir = "/vault",
        query = "query",
        callback = function(entries)
          grepped = entries
        end,
        selection_mappings = {
          ["<C-l>"] = {
            desc = "map",
            allow_multiple = true,
            callback = function(...)
              mapped = { ... }
            end,
          },
        },
      }
    end)
  end)

  eq({ "/vault/one.md", "/vault/two.md" }, mapped)
  eq({
    { filename = "/vault/one.md", lnum = 2, col = 3 },
    { filename = "/vault/two.md" },
  }, grepped)
end

T["telescope grep mappings receive paths"] = function()
  local mapped
  with_obsidian({ opts = { search = { sort_by = false, sort_reversed = false } } }, function()
    with_modules({
      ["telescope.actions"] = {
        close = function() end,
      },
      ["telescope.actions.state"] = {
        get_current_picker = function()
          return {
            get_multi_selection = function()
              return { { filename = "/vault/note.md", lnum = 2, col = 3 } }
            end,
          }
        end,
      },
      ["telescope.builtin"] = {
        grep_string = function(opts)
          local mappings = {}
          opts.attach_mappings(1, function(_, key, callback)
            mappings[key] = callback
          end)
          mappings["<C-l>"](1)
        end,
      },
    }, function()
      require("obsidian.picker.telescope").grep {
        dir = "/vault",
        query = "query",
        selection_mappings = {
          ["<C-l>"] = {
            desc = "map",
            callback = function(path)
              mapped = path
            end,
          },
        },
      }
    end)
  end)
  eq("/vault/note.md", mapped)
end

T["snacks grep mappings receive paths"] = function()
  local mapped
  with_obsidian({ opts = { search = { sort_by = false, sort_reversed = false } } }, function()
    with_module("snacks.picker", {
      pick = function(opts)
        opts.actions.map({
          close = function() end,
        }, { _path = "/vault/note.md" })
      end,
    }, function()
      require("obsidian.picker.snacks").grep {
        dir = "/vault",
        query = "query",
        selection_mappings = {
          ["<C-l>"] = {
            desc = "map",
            callback = function(path)
              mapped = path
            end,
          },
        },
      }
      vim.wait(1000, function()
        return mapped ~= nil
      end)
    end)
  end)
  eq("/vault/note.md", mapped)
end

return T
