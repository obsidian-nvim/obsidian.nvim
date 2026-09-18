local ui = require "obsidian.ui"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["ExtMark"] = new_set()

T["ExtMark"]["should match == with other ExtMark instances"] = function()
  local m1 = ui.ExtMark.new(
    nil,
    1,
    0,
    ui.ExtMarkOpts.from_tbl {
      end_row = 1,
      end_col = 2,
      conceal = "",
    }
  )
  local m2 = ui.ExtMark.new(
    0,
    1,
    0,
    ui.ExtMarkOpts.from_tbl {
      end_row = 1,
      end_col = 2,
      conceal = "",
    }
  )
  eq(m1, m2)

  m1 = ui.ExtMark.new(
    nil,
    58,
    2,
    ui.ExtMarkOpts.from_tbl {
      end_row = 58,
      end_col = 29,
      conceal = "",
    }
  )
  m2 = ui.ExtMark.new(
    62,
    58,
    2,
    ui.ExtMarkOpts.from_tbl {
      end_row = 58,
      end_col = 29,
      conceal = "",
    }
  )
  eq(m1, m2)
end

T["update"] = new_set()

T["update"]["should not add tag extmarks inside inline code"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".md")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "`foo #bar` #baz" })

  Obsidian = {
    opts = {
      ui = vim.deepcopy(require("obsidian.config.default").ui),
    },
  }

  ui.update(bufnr)

  local ns_id = vim.api.nvim_create_namespace "ObsidianUI"
  local tag_marks = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })) do
    if mark[4].hl_group == "ObsidianTag" then
      tag_marks[#tag_marks + 1] = mark
    end
  end

  eq(1, #tag_marks)
  eq(11, tag_marks[1][3])
end

return T
