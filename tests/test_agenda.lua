local h = dofile "tests/helpers.lua"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local parser = require "obsidian.agenda.parser"
local dates = require "obsidian.agenda.dates"

local T = new_set()

T["parser"] = new_set()

T["parser"]["parses checkbox task metadata"] = function()
  local item = parser.parse_line("- [ ] Pay rent @due(2026-06-01) #home [#A]", { path = "agenda.md", lnum = 3 })
  eq("todo", item.status)
  eq("Pay rent #home", item.title)
  eq("A", item.priority)
  eq({ "home" }, item.tags)
  eq("2026-06-01", dates.format(item.due))
  eq("agenda.md", item.path)
  eq(3, item.lnum)
end

T["parser"]["parses scheduled date and done status"] = function()
  local item = parser.parse_line "- [x] Ship it @scheduled(2026-05-29) @done(2026-05-30)"
  eq("done", item.status)
  eq("Ship it", item.title)
  eq("2026-05-29", dates.format(item.scheduled))
  eq("2026-05-30", dates.format(item.done))
end

T["integration"] = h.temp_vault

T["integration"]["week respects start_of_week and includes undated"] = function()
  local views = require "obsidian.agenda.views"
  Obsidian.opts.date.start_of_week = 0
  local items = parser.parse_lines {
    "- [ ] Monday task @2026-06-01",
    "- [ ] No date",
  }
  local view = views.week(items, dates.parse "2026-06-03")
  eq("Obsidian Agenda: Week of 2026-05-31", view.title)
  eq("Undated", view.sections[#view.sections].title)
  eq("No date", view.sections[#view.sections].items[1].item.title)
end

T["integration"]["custom get_items can finish asynchronously"] = function()
  local agenda = require "obsidian.agenda"
  Obsidian.opts.agenda.get_items = function(_, done)
    vim.schedule(function()
      done { { title = "Async task", status = "todo" } }
    end)
  end

  agenda.open { view = "todo" }
  vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find "Async task" ~= nil
  end)
  local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  eq(true, lines:find "Async task" ~= nil)
end

T["integration"]["opens default file agenda in quickfix"] = function()
  local agenda = require "obsidian.agenda"
  h.write("- [ ] No date", Obsidian.dir / "agenda.md")
  agenda.open { view = "todo" }
  vim.wait(1000, function()
    return vim.fn.getqflist({ title = 0 }).title == "Obsidian Agenda: Todo"
  end)
  local qf = vim.fn.getqflist { items = 0, title = 0 }
  eq("Obsidian Agenda: Todo", qf.title)
  eq("No date", qf.items[1].text:match "No date")
  eq(
    vim.fs.normalize(tostring((Obsidian.dir / "agenda.md"):resolve())),
    vim.fs.normalize(vim.api.nvim_buf_get_name(qf.items[1].bufnr))
  )
end

T["integration"]["buffer renderer remains available"] = function()
  local agenda = require "obsidian.agenda"
  Obsidian.opts.agenda.ui.renderer = "buffer"
  h.write("- [ ] Buffer task", Obsidian.dir / "agenda.md")
  local bufnr = agenda.open { view = "todo" }
  vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):find "Buffer task" ~= nil
  end)
  eq("obsidian-agenda", vim.bo[bufnr].filetype)
end

T["integration"]["task.resolve uses agenda file by default and allows path override"] = function()
  local agenda = require "obsidian.agenda"
  local default_item = agenda.task.resolve { title = "Default target" }
  eq(vim.fs.normalize(tostring((Obsidian.dir / "agenda.md"):resolve())), vim.fs.normalize(default_item.path))
  eq(1, default_item.lnum)

  local override_item = agenda.task.resolve({ title = "Override target", path = "other.md", lnum = 7 }, {
    default_path = Obsidian.dir / "agenda.md",
  })
  eq(vim.fs.normalize(tostring((Obsidian.dir / "other.md"):resolve())), vim.fs.normalize(override_item.path))
  eq(7, override_item.lnum)
end

return T
