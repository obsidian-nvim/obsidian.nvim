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

local function with_qf_spy(fn)
  local picker_util = require "obsidian.picker.util"
  local original = picker_util.send_to_qf
  local calls = {}
  picker_util.send_to_qf = function(items, opts)
    calls[#calls + 1] = { items = items, opts = opts }
  end
  local ok, err = pcall(fn)
  vim.wait(1000, function()
    return #calls > 0
  end)
  picker_util.send_to_qf = original
  if not ok then
    error(err)
  end
  return calls
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

T["mini quickfix action exports marks or current filtered matches"] = function()
  local first = { filename = "/vault/first.md" }
  local second = { filename = "/vault/second.md" }
  local sent
  local selected
  local original_send = require("obsidian.picker.util").send_to_qf

  local calls = with_qf_spy(function()
    with_module("mini.pick", {
      get_picker_matches = function()
        return { marked = {}, all = { { obsidian_item = first }, { obsidian_item = second } } }
      end,
      start = function(opts)
        opts.mappings.obsidian_selection__C_q_.func()
        return nil
      end,
    }, function()
      require("obsidian.picker.mini").select({ first, second }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Mini" },
        },
      }, function(items)
        selected = items
      end)
    end)
  end)
  require("obsidian.picker.util").send_to_qf = original_send
  sent = calls[1]

  eq({ first, second }, sent.items)
  eq("Mini", sent.opts.title)
  eq(nil, selected)
end

T["mini quickfix action prefers marked values"] = function()
  local marked = { filename = "/vault/marked.md" }
  local filtered = { filename = "/vault/filtered.md" }
  local sent
  local calls = with_qf_spy(function()
    with_module("mini.pick", {
      get_picker_matches = function()
        return { marked = { { obsidian_item = marked } }, all = { { obsidian_item = filtered } } }
      end,
      start = function(opts)
        opts.mappings.obsidian_selection__C_q_.func()
      end,
    }, function()
      require("obsidian.picker.mini").select({ marked, filtered }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Mini marked" },
        },
      })
    end)
  end)
  sent = calls[1]
  eq({ marked }, sent.items)
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

T["fzf quickfix action bypasses normal callback for selected values"] = function()
  local first = { filename = "/vault/first.md" }
  local sent
  local toggle_callbacks = {}
  local calls = with_qf_spy(function()
    with_modules({
      ["fzf-lua.previewer.builtin"] = {},
      ["fzf-lua.shell"] = {
        stringify_data = function(callback)
          toggle_callbacks[#toggle_callbacks + 1] = callback
          return "mock-transform"
        end,
      },
      ["fzf-lua"] = {
        fzf_exec = function(entries, opts)
          eq("mock-transform", opts.keymap.fzf.tab)
          opts.actions["ctrl-q"]({ entries[1] }, { query = "" })
        end,
      },
    }, function()
      require("obsidian.picker.fzf").select({ first }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Fzf" },
        },
      }, function()
        error "quickfix action must not call on_choice"
      end)
    end)
  end)
  sent = calls[1]

  eq({ first }, sent.items)
  eq("Fzf", sent.opts.title)
end

T["fzf quickfix action exports the exact fzf-filtered set with no marks"] = function()
  local values = {
    { filename = "/vault/one.md", text = "alpha one" },
    { filename = "/vault/two.md", text = "beta" },
    { filename = "/vault/three.md", text = "alpha three" },
  }
  local sent
  local filter_argv
  local original_system = vim.system
  local calls = with_qf_spy(function()
    vim.system = function(command, options)
      filter_argv = command
      eq(table.concat({ "1\talpha one", "2\tbeta", "3\talpha three" }, "\n"), options.stdin)
      return {
        wait = function()
          return { code = 0, stdout = "1\talpha one\n3\talpha three\n" }
        end,
      }
    end
    with_modules({
      ["fzf-lua.previewer.builtin"] = {},
      ["fzf-lua.shell"] = {
        stringify_data = function()
          return "mock-transform"
        end,
      },
      ["fzf-lua"] = {
        get_last_query = function()
          return "alpha"
        end,
        fzf_exec = function(entries, opts)
          opts.actions["ctrl-q"]({ entries[2] }, { fzf_opts = {} })
        end,
      },
    }, function()
      require("obsidian.picker.fzf").select(values, {
        query = "alpha",
        format_item = function(value)
          return value.text
        end,
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Filtered" },
        },
      }, function()
        error "quickfix must bypass on_choice"
      end)
    end)
    vim.system = original_system
  end)
  sent = calls[1]

  eq("--filter", filter_argv[2])
  eq("alpha", filter_argv[3])
  eq({ values[1], values[3] }, sent.items)
end

T["fzf quickfix filtered export uses the installed fzf matcher without opening its UI"] = function()
  if vim.fn.executable "fzf" ~= 1 then
    return
  end
  local values = {
    { filename = "/vault/a.md", text = "alpha first" },
    { filename = "/vault/b.md", text = "beta" },
    { filename = "/vault/c.md", text = "alpha last" },
  }
  local sent
  local calls = with_qf_spy(function()
    with_modules({
      ["fzf-lua.previewer.builtin"] = {},
      ["fzf-lua.shell"] = {
        stringify_data = function()
          return "mock-transform"
        end,
      },
      ["fzf-lua"] = {
        get_last_query = function()
          return "alpha"
        end,
        fzf_exec = function(entries, opts)
          opts.actions["ctrl-q"]({ entries[2] }, { query = "alpha", fzf_opts = opts.fzf_opts })
        end,
      },
    }, function()
      require("obsidian.picker.fzf").select(values, {
        query = "alpha",
        format_item = function(value)
          return value.text
        end,
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Fzf exact filter" },
        },
      })
    end)
  end)
  sent = calls[1]
  local entries = { "1\talpha first", "2\tbeta", "3\talpha last" }
  local filtered = vim
    .system({
      "fzf",
      "--filter",
      "alpha",
      "--delimiter",
      "\t",
      "--with-nth",
      "2..",
    }, { stdin = table.concat(entries, "\n"), text = true })
    :wait()
  local expected = {}
  for _, entry in ipairs(vim.split((filtered.stdout or ""):gsub("\r", ""), "\n", { plain = true, trimempty = true })) do
    local index = tonumber(entry:match "^(%d+)\t")
    expected[#expected + 1] = values[index]
  end
  eq(expected, sent.items)
end

T["fzf quickfix action preserves a lone explicit mark"] = function()
  local values = {
    { filename = "/vault/alpha.md", text = "alpha" },
    { filename = "/vault/beta.md", text = "beta" },
  }
  local sent
  local toggle_callback
  local original_system = vim.system
  local calls = with_qf_spy(function()
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = "1\talpha\n" }
        end,
      }
    end
    with_modules({
      ["fzf-lua.previewer.builtin"] = {},
      ["fzf-lua.shell"] = {
        stringify_data = function(callback)
          toggle_callback = toggle_callback or callback
          return "mock-transform"
        end,
      },
      ["fzf-lua"] = {
        get_last_query = function()
          return "alpha"
        end,
        fzf_exec = function(entries, opts)
          toggle_callback { entries[2] }
          opts.actions["ctrl-q"]({ entries[2] }, { fzf_opts = {} })
        end,
      },
    }, function()
      require("obsidian.picker.fzf").select(values, {
        query = "alpha",
        format_item = function(value)
          return value.text
        end,
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Marked" },
        },
      })
    end)
    vim.system = original_system
  end)
  sent = calls[1]

  eq({ values[2] }, sent.items)
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

T["fzf select overrides the fzf-tmux border for builtin previews"] = function()
  local border = assert(loadstring("return function() end", "@/tmp/fzf-tmux.lua"))()

  with_modules({
    ["fzf-lua.config"] = {
      globals = { winopts = { preview = { border = border } } },
    },
    ["fzf-lua.previewer.builtin"] = {
      buffer_or_file = {
        extend = function()
          return {}
        end,
      },
    },
    ["fzf-lua"] = {
      fzf_exec = function(_, opts)
        eq({ preview = { border = "rounded" } }, { preview = opts.winopts.preview })
        eq("function", type(opts.winopts.on_close))
      end,
    },
  }, function()
    require("obsidian.picker.fzf").select({ "one" }, {
      preview_item = function()
        return { buf = vim.api.nvim_create_buf(false, true) }
      end,
    })
  end)
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

T["snacks quickfix action exports marked items before filtered matches"] = function()
  local marked = { obsidian_item = { filename = "/vault/marked.md" } }
  local filtered = { obsidian_item = { filename = "/vault/filtered.md" } }
  local sent
  local calls = with_qf_spy(function()
    with_module("snacks.picker", {
      pick = function(opts)
        local picker = {
          list = { items = { filtered } },
          selected = function()
            return { marked }
          end,
          close = function() end,
        }
        opts.actions.send_to_quickfix(picker, filtered)
      end,
    }, function()
      require("obsidian.picker.snacks").select({ marked.obsidian_item, filtered.obsidian_item }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Snacks" },
        },
      }, function()
        error "quickfix action must not call on_choice"
      end)
    end)
  end)
  sent = calls[1]

  eq({ marked.obsidian_item }, sent.items)
  eq("Snacks", sent.opts.title)
end

T["snacks quickfix action exports filtered results when no marks exist"] = function()
  local first = { obsidian_item = { filename = "/vault/one.md" } }
  local second = { obsidian_item = { filename = "/vault/two.md" } }
  local sent
  local calls = with_qf_spy(function()
    with_module("snacks.picker", {
      pick = function(opts)
        opts.actions.send_to_quickfix({
          selected = function()
            return {}
          end,
          list = { items = { first, second } },
          close = function() end,
        }, second)
      end,
    }, function()
      require("obsidian.picker.snacks").select({ first.obsidian_item, second.obsidian_item }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Snacks filtered" },
        },
      })
    end)
  end)
  sent = calls[1]
  eq({ first.obsidian_item, second.obsidian_item }, sent.items)
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

T["telescope quickfix action uses filtered results when no items are marked"] = function()
  local first = { filename = "/vault/one.md", text = "same" }
  local second = { filename = "/vault/two.md", text = "same" }
  local sent
  local callbacks = {}
  local calls = with_qf_spy(function()
    with_modules({
      ["telescope.actions"] = { close = function() end },
      ["telescope.actions.state"] = {
        get_current_picker = function()
          return {
            get_multi_selection = function()
              return {}
            end,
            manager = {
              num_results = function()
                return 2
              end,
              get_entry = function(_, index)
                return { obsidian_item = index == 1 and first or second }
              end,
            },
          }
        end,
      },
      ["telescope.pickers"] = {
        new = function(_, opts)
          return {
            find = function()
              opts.attach_mappings(1, function(_, key, callback)
                callbacks[key] = callback
              end)
              callbacks["<C-q>"](1)
            end,
          }
        end,
      },
      ["telescope.finders"] = {
        new_table = function(opts)
          return opts
        end,
      },
      ["telescope.config"] = { values = {
        generic_sorter = function()
          return {}
        end,
      } },
    }, function()
      require("obsidian.picker.telescope").select({ first, second }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Telescope" },
        },
      }, function()
        error "quickfix action must not call on_choice"
      end)
    end)
  end)
  sent = calls[1]

  eq({ first, second }, sent.items)
  eq("Telescope", sent.opts.title)
end

T["telescope quickfix action prefers marked values"] = function()
  local first = { filename = "/vault/first.md" }
  local marked = { filename = "/vault/marked.md" }
  local sent
  local calls = with_qf_spy(function()
    with_modules({
      ["telescope.actions"] = { close = function() end },
      ["telescope.actions.state"] = {
        get_current_picker = function()
          return {
            get_multi_selection = function()
              return { { obsidian_item = marked } }
            end,
            manager = {
              num_results = function()
                return 2
              end,
              get_entry = function(_, index)
                return { obsidian_item = index == 1 and first or marked }
              end,
            },
          }
        end,
      },
      ["telescope.pickers"] = {
        new = function(_, opts)
          return {
            find = function()
              local mapped
              opts.attach_mappings(1, function(_, _, callback)
                mapped = callback
              end)
              mapped(1)
            end,
          }
        end,
      },
      ["telescope.finders"] = {
        new_table = function(opts)
          return opts
        end,
      },
      ["telescope.config"] = { values = {
        generic_sorter = function()
          return {}
        end,
      } },
    }, function()
      require("obsidian.picker.telescope").select({ first, marked }, {
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = require("obsidian.picker.util").send_to_qf_mapping { title = "Telescope marked" },
        },
      })
    end)
  end)
  sent = calls[1]
  eq({ marked }, sent.items)
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
        cmd = require("obsidian.search").build_grep_cmd(),
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
        cmd = require("obsidian.search").build_grep_cmd(),
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
