--- Floating markdown editor input.
--- Opens a centered floating window with a real markdown buffer,
--- so that obsidian.nvim features (completion, wiki links, etc.) work.
--- Resolves with the buffer content when the user confirms (<CR> in normal mode or :wq).

local M = {}

---@class obsidian.editor.Opts
---@field default string? Initial content
---@field title string? Window title
---@field width integer? Window width (default 60)
---@field height integer? Window height (default 8)

---@param prompt string
---@param opts obsidian.editor.Opts?
---@param callback fun(result: string?)
M.open = function(prompt, opts, callback)
  opts = opts or {}
  local width = opts.width or 60
  local height = opts.height or 8

  callback = vim.schedule_wrap(callback)

  local buf = vim.api.nvim_create_buf(false, true)

  -- Place the buffer in the workspace so obsidian autocmds fire.
  local tmp_name = tostring(Obsidian.workspace.root / (".obsidian-editor-input-%d.md"):format(buf))
  vim.api.nvim_buf_set_name(buf, tmp_name)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = ""
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false

  -- Seed with default content.
  if opts.default and opts.default ~= "" then
    local lines = vim.split(opts.default, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  -- Compute centered position.
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local title = prompt
  if not vim.endswith(title, ": ") then
    title = title .. ": "
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. title,
    title_pos = "left",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local closed = false

  local function finish(cancelled)
    if closed then
      return
    end
    closed = true

    local result
    if not cancelled then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Trim trailing empty lines.
      while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
      end
      result = table.concat(lines, "\n")
    end

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    vim.schedule(function()
      callback(result)
    end)
  end

  -- <CR> in normal mode confirms.
  vim.keymap.set("n", "<CR>", function()
    finish(false)
  end, { buffer = buf, nowait = true })

  -- q or <Esc> in normal mode cancels.
  vim.keymap.set("n", "q", function()
    finish(true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    finish(true)
  end, { buffer = buf, nowait = true })

  -- Handle :w / :wq via BufWriteCmd so the buffer is never written to disk.
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      -- Mark as not modified so :wq doesn't complain.
      vim.bo[buf].modified = false
      finish(false)
    end,
  })

  -- If the window is closed by other means (e.g. :q without write), treat as cancel.
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    callback = function()
      finish(true)
    end,
  })
end

return M
