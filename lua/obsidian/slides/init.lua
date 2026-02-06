--- adaptated from https://github.com/tjdevries/present.nvim
local M = {}
local parser = require "obsidian.slides.parse"
local log = require "obsidian.log"

---@param config vim.api.keyset.win_config
---@param enter boolean
local function create_floating_window(config, enter)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, enter or false, config)
  return { buf = buf, win = win }
end

---@class obsidian.Config.SlidesOpts
---@field padding integer
local options = {
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
      border = "none",
    },
    body = {
      relative = "editor",
      width = width - (options.padding * 2),
      height = body_height,
      style = "minimal",
      col = options.padding,
      row = 1,
      border = "none",
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
      border = "none",
    },
  }
end

local state = {
  slides = {},
  ---@type integer?
  current_slide = nil,
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

---@param note obsidian.Note
M.start_presentation = function(note)
  local lines = {}

  --- TODO: note:body_lines()
  if note.has_frontmatter and note.frontmatter_end_line then
    for i = note.frontmatter_end_line + 1, #note.contents do
      lines[#lines + 1] = note.contents[i]
    end
  else
    lines = note.contents
  end

  state.slides = parser.parse(lines)
  state.current_slide = 1

  local windows = create_window_configurations()
  state.floats.background = create_floating_window(windows.background, false)
  state.floats.footer = create_floating_window(windows.footer, false)
  state.floats.body = create_floating_window(windows.body, true)

  vim.bo[state.floats.body.buf].filetype = "markdown"
  vim.wo[state.floats.body.win].spell = false

  -- TODO: make customizable, with context of windows and buffers
  local set_slide_content = function(idx)
    foreach_float(function(_, float)
      vim.bo[float.buf].modifiable = true
    end)
    local slide = state.slides[idx]

    if not slide then
      log.err "failed to get slides"
      return
    end

    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, { slide.title, "" })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, -1, -1, false, slide.body)

    local footer = string.format("  %d / %d | %s", state.current_slide, #state.slides, note.title or note.id)
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
    end,
  })

  set_slide_content(state.current_slide)
end

return M
