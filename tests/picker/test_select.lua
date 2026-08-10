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

local function with_select(select_impl, fn)
  local original_select = vim.ui.select
  vim.ui.select = select_impl
  local ok, err = pcall(fn)
  vim.ui.select = original_select
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

T["snacks setup registers workspace sources"] = function()
  local sources = {}
  local integration = require "obsidian.picker.integration"
  local original_workspace_dir = integration.workspace_dir
  local configured

  local ok, err = pcall(function()
    integration.workspace_dir = function()
      return "/vault/current"
    end
    with_module("snacks.picker.config.sources", sources, function()
      require("obsidian.picker.snacks").setup {
        find_files = { hidden = true },
        grep = { regex = false },
      }
      configured = sources.obsidian_files.config {}
    end)
  end)

  integration.workspace_dir = original_workspace_dir
  if not ok then
    error(err)
  end

  eq("files", sources.obsidian_files.finder)
  eq(true, sources.obsidian_files.hidden)
  eq("/vault/current", configured.cwd)
  eq("grep", sources.obsidian_grep.finder)
  eq(false, sources.obsidian_grep.regex)
end

T["fzf setup registers workspace providers"] = function()
  local integration = require "obsidian.picker.integration"
  local original_workspace_dir = integration.workspace_dir
  local files_opts
  local grep_opts
  local fzf = {
    files = function(opts)
      files_opts = opts
    end,
    live_grep = function(opts)
      grep_opts = opts
    end,
  }
  fzf.register_extension = function(name, callback)
    fzf[name] = callback
  end

  local ok, err = pcall(function()
    integration.workspace_dir = function()
      return "/vault/current"
    end
    with_module("fzf-lua", fzf, function()
      require("obsidian.picker.fzf").setup {
        find_files = { hidden = true },
        grep = { no_ignore = true },
      }
      fzf.obsidian_files { follow = true, cwd = "/ignored" }
      fzf.obsidian_grep { search = "needle" }
    end)
  end)

  integration.workspace_dir = original_workspace_dir
  if not ok then
    error(err)
  end

  eq({ cwd = "/vault/current", follow = true, hidden = true }, files_opts)
  eq("/vault/current", grep_opts.cwd)
  eq(true, grep_opts.no_ignore)
  eq("needle", grep_opts.search)
end

T["mini setup registers workspace pickers"] = function()
  local integration = require "obsidian.picker.integration"
  local original_workspace_dir = integration.workspace_dir
  local files_local_opts
  local files_opts
  local grep_local_opts
  local grep_opts
  local mini = {
    registry = {},
    builtin = {
      files = function(local_opts, opts)
        files_local_opts = local_opts
        files_opts = opts
      end,
      grep_live = function(local_opts, opts)
        grep_local_opts = local_opts
        grep_opts = opts
      end,
    },
  }

  local ok, err = pcall(function()
    integration.workspace_dir = function()
      return "/vault/current"
    end
    with_module("mini.pick", mini, function()
      require("obsidian.picker.mini").setup {
        find_files = { tool = "rg" },
        grep = { globs = { "*.md" } },
      }
      mini.registry.obsidian_files { hidden = true }
      mini.registry.obsidian_grep { pattern = "needle" }
    end)
  end)

  integration.workspace_dir = original_workspace_dir
  if not ok then
    error(err)
  end

  eq({ hidden = true, tool = "rg" }, files_local_opts)
  eq({ source = { cwd = "/vault/current", name = "Obsidian Files" } }, files_opts)
  eq({ globs = { "*.md" }, pattern = "needle" }, grep_local_opts)
  eq({ source = { cwd = "/vault/current", name = "Obsidian Grep" } }, grep_opts)
end

T["telescope setup loads extension and exports workspace pickers"] = function()
  local integration = require "obsidian.picker.integration"
  local original_workspace_dir = integration.workspace_dir
  local loaded
  local files_opts
  local grep_opts

  local ok, err = pcall(function()
    integration.workspace_dir = function()
      return "/vault/current"
    end
    with_modules({
      telescope = {
        load_extension = function(name)
          loaded = name
        end,
      },
      ["telescope.builtin"] = {
        find_files = function(opts)
          files_opts = opts
        end,
        live_grep = function(opts)
          grep_opts = opts
        end,
      },
    }, function()
      local telescope = require "obsidian.picker.telescope"
      telescope.setup {
        find_files = { hidden = true },
        grep = { additional_args = { "--hidden" } },
      }
      telescope.workspace_files { follow = true }
      telescope.workspace_grep { default_text = "needle" }
    end)
  end)

  integration.workspace_dir = original_workspace_dir
  if not ok then
    error(err)
  end

  eq("obsidian", loaded)
  eq({ cwd = "/vault/current", follow = true, hidden = true }, files_opts)
  eq("/vault/current", grep_opts.cwd)
  eq({ "--hidden" }, grep_opts.additional_args)
  eq("needle", grep_opts.default_text)
end

return T
