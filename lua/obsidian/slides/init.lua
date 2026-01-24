local M = {}
local Note = require "obsidian.note"
local parser = require "obsidian.slides.parse"

local function create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, enter or false, config)

  return { buf = buf, win = win }
end

---@class present.Options
---@field syntax present.SyntaxOptions: The syntax for the plugin

---@class present.SyntaxOptions
---@field comment string?: The prefix for comments, will skip lines that start with this
---@field stop string?: The stop comment, will stop slide when found. Note: Is a Lua Pattern

---@type present.Options
local options = {
  syntax = {
    comment = "%%", -- TODO: proper use of vim.o.commentstring
    stop = "---",
  },
  padding = 4,
}

local create_window_configurations = function()
  local width = vim.o.columns
  local height = vim.o.lines

  local footer_height = 1 -- 1, no border
  local body_height = height - footer_height - 2 - 1 -- for our own border

  return {
    background = {
      relative = "editor",
      width = width,
      height = height,
      style = "minimal",
      col = 0,
      row = 0,
      zindex = 1,
    },
    body = {
      relative = "editor",
      width = width - (options.padding * 2),
      height = body_height,
      style = "minimal",
      col = options.padding,
      row = 1,
    },
    -- TODO: 0.12 can be just a statusline that aligns right
    footer = {
      relative = "editor",
      width = width,
      height = 1,
      style = "minimal",
      col = 0,
      row = height - 1,
      zindex = 3,
    },
  }
end

local state = {
  slides = {},
  current_slide = 1,
  floats = {},
}

local foreach_float = function(cb)
  for name, float in pairs(state.floats) do
    cb(name, float)
  end
end

local present_keymap = function(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.floats.body.buf,
  })
end

---@param buf integer
M.start_presentation = function(buf)
  buf = buf or 0

  local note = Note.from_buffer(buf)

  local lines = {}

  if note.has_frontmatter then
    for i = note.frontmatter_end_line + 1, #note.contents do
      lines[#lines + 1] = note.contents[i]
    end
  else
    lines = note.contents
  end
  ---@cast lines -nil

  state.slides = parser.parse(lines)
  state.current_slide = 1
  state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")

  local windows = create_window_configurations()
  state.floats.background = create_floating_window(windows.background)
  state.floats.footer = create_floating_window(windows.footer)
  state.floats.body = create_floating_window(windows.body, true)

  vim.bo[state.floats.body.buf].filetype = "markdown"
  vim.wo[state.floats.body.win].spell = false

  -- TODO: make customizable, with context of windows and buffers
  local set_slide_content = function(idx)
    foreach_float(function(_, float)
      vim.bo[float.buf].modifiable = true
    end)
    local slide = state.slides[idx]

    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, { slide.title, "" })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, -1, -1, false, slide.body)

    local footer = string.format("  %d / %d | %s", state.current_slide, #state.slides, state.title)
    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })

    pcall(vim.api.nvim_win_set_cursor, state.floats.body.win, { 2, 0 }) -- to not cover the title

    foreach_float(function(_, float)
      vim.bo[float.buf].modifiable = false
    end)
  end

  present_keymap("n", "n", function()
    if state.current_slide == #state.slides then
      return
    end
    state.current_slide = math.min(state.current_slide + 1, #state.slides)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "p", function()
    if state.current_slide == 1 then
      return
    end
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "q", function()
    vim.api.nvim_win_close(state.floats.body.win, true)
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0,
    },
    guicursor = {
      original = vim.o.guicursor,
      present = "n:NormalFloat",
    },
    wrap = {
      original = vim.o.wrap,
      present = true,
    },
    breakindent = {
      original = vim.o.breakindent,
      present = true,
    },
    breakindentopt = {
      original = vim.o.breakindentopt,
      present = "list:-1",
    },
  }

  -- Set the options we want during presentation
  for option, config in pairs(restore) do
    vim.opt[option] = config.present
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.floats.body.buf,
    callback = function()
      -- Reset the values when we are done with the presentation
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end

      foreach_float(function(_, float)
        pcall(vim.api.nvim_win_close, float.win, true)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present-resized", {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then
        return
      end

      local updated = create_window_configurations()
      foreach_float(function(name, _)
        vim.api.nvim_win_set_config(state.floats[name].win, updated[name])
      end)

      -- -- Re-calculates current slide contents
      -- set_slide_content(state.current_slide)
    end,
  })

  set_slide_content(state.current_slide)
end

return M
