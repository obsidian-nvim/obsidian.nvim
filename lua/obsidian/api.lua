local M = {}
local log = require "obsidian.log"
local util = require "obsidian.util"
local iter, string, table = vim.iter, string, table
local Path = require "obsidian.path"
local search = require "obsidian.search"
local config = require "obsidian.config"
local ns_id = vim.api.nvim_create_namespace "ObsidianApi"

---@param dir string | obsidian.Path
---@return Iter
M.dir = function(dir)
  dir = tostring(dir)
  local dir_opts = {
    depth = 10,
    skip = function(p)
      return not vim.startswith(p, ".") and p ~= vim.fs.basename(tostring(M.templates_dir()))
    end,
  }

  return vim
    .iter(vim.fs.dir(dir, dir_opts))
    :filter(function(path)
      return vim.endswith(path, ".md")
    end)
    :map(function(path)
      return vim.fs.joinpath(dir, path)
    end)
end

--- Get the templates folder.
---
---@param workspace obsidian.Workspace?
---@return obsidian.Path|?
M.templates_dir = function(workspace)
  local opts = Obsidian.opts

  if workspace and workspace ~= Obsidian.workspace then
    opts = config.normalize(workspace.overrides, Obsidian._opts)
  end

  if opts.templates == nil or opts.templates.folder == nil then
    return nil
  end

  local paths_to_check = { Obsidian.workspace.root / opts.templates.folder, Path.new(opts.templates.folder) }
  for _, path in ipairs(paths_to_check) do
    if path:is_dir() then
      return path
    end
  end

  log.err_once("'%s' is not a valid templates directory", opts.templates.folder)
  return nil
end

--- Check if a path represents a note in the workspace.
---
---@param path string|obsidian.Path
---@param workspace obsidian.Workspace|?
---
---@return boolean
M.path_is_note = function(path, workspace)
  path = Path.new(path):resolve()
  workspace = workspace or Obsidian.workspace

  local in_vault = path.filename:find(vim.pesc(tostring(workspace.root))) ~= nil
  if not in_vault then
    return false
  end

  -- Notes have to be markdown file.
  if path.suffix ~= ".md" then
    return false
  end

  -- Ignore markdown files in the templates directory.
  local templates_dir = M.templates_dir(workspace)
  if templates_dir ~= nil then
    if templates_dir:is_parent_of(path) then
      return false
    end
  end

  return true
end

--- Get the current note from a buffer.
---
---@param bufnr integer|?
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note|?
---@diagnostic disable-next-line: unused-local
M.current_note = function(bufnr, opts)
  bufnr = bufnr or 0
  local Note = require "obsidian.note"
  if not M.path_is_note(vim.api.nvim_buf_get_name(bufnr)) then
    return nil
  end

  opts = opts or {}
  if not opts.max_lines then
    opts.max_lines = Obsidian.opts.search_max_lines
  end
  return Note.from_buffer(bufnr, opts)
end

---builtin functions that are impure, interacts with editor state, like vim.api

---Toggle the checkbox on the current line.
---
---@param states table|nil Optional table containing checkbox states (e.g., {" ", "x"}).
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.toggle_checkbox = function(states, line_num)
  if not util.in_node { "list", "paragraph" } or util.in_node "block_quote" then
    return
  end
  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  local checkboxes = states or { " ", "x" }

  if util.is_checkbox(line) then
    for i, check_char in ipairs(checkboxes) do
      if string.match(line, "^.* %[" .. vim.pesc(check_char) .. "%].*") then
        i = i % #checkboxes
        line = string.gsub(line, vim.pesc("[" .. check_char .. "]"), "[" .. checkboxes[i + 1] .. "]", 1)
        break
      end
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(line, unordered_list_pattern) then
      line = string.gsub(line, unordered_list_pattern, "%1- [ ] %2")
    else
      line = string.gsub(line, "^(%s*)", "%1- [ ] ")
    end
  else
    goto out
  end

  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { line })
  ::out::
end

---Set the checkbox on the current line to a specific state.
---
---@param state string|nil Optional string of state to set the checkbox to (e.g., " ", "x").
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.set_checkbox = function(state, line_num)
  if not util.in_node { "list", "paragraph" } or util.in_node "block_quote" then
    return
  end

  if state == "" then
    local ok, key = pcall(vim.fn.getchar)
    if not ok then return end
    state = string.char(key)
  end

  local found = false
  for _, value in ipairs(Obsidian.opts.checkbox.order) do
    if value == state then
      found = true
    end
  end

  if not found then
    log.err("state passed \"" .. state .. "\" is not part of the available states: " .. vim.inspect(Obsidian.opts.checkbox.order))
    return
  end

  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  if util.is_checkbox(line) then
    if string.match(line, "^.* %[.%].*") then
      line = string.gsub(line, "%[.%]", "[" .. state .. "]", 1)
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(line, unordered_list_pattern) then
      line = string.gsub(line, unordered_list_pattern, "%1- [".. state .. "] %2")
    else
      line = string.gsub(line, "^(%s*)", "%1- [".. state .. "] ")
    end
  else
    goto out
  end

  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { line })
  ::out::
end

---@return [number, number, number, number] tuple containing { buf, win, row, col }
M.get_active_window_cursor_location = function()
  local buf = vim.api.nvim_win_get_buf(0)
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local location = { buf, win, row, col }
  return location
end

--- Create a formatted markdown / wiki link for a note.
---
---@param note obsidian.Note|obsidian.Path|string The note/path to link to.
---@param opts { label: string|?, link_style: obsidian.config.LinkStyle|?, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }|? Options.
---
---@return string
M.format_link = function(note, opts)
  opts = opts or {}

  ---@type string, string, string|integer|?
  local rel_path, label, note_id
  if type(note) == "string" or Path.is_path_obj(note) then
    ---@cast note string|obsidian.Path
    -- rel_path = tostring(self:vault_relative_path(note, { strict = true }))
    rel_path = assert(Path.new(note):vault_relative_path { strict = true })
    label = opts.label or tostring(note)
    note_id = opts.id
  else
    ---@cast note obsidian.Note
    -- rel_path = tostring(self:vault_relative_path(note.path, { strict = true }))
    rel_path = assert(note.path:vault_relative_path { strict = true })
    label = opts.label or note:display_name()
    note_id = opts.id or note.id
  end

  local link_style = opts.link_style
  if link_style == nil then
    link_style = Obsidian.opts.preferred_link_style
  end

  local new_opts = { path = rel_path, label = label, id = note_id, anchor = opts.anchor, block = opts.block }

  if link_style == config.LinkStyle.markdown then
    return Obsidian.opts.markdown_link_func(new_opts)
  elseif link_style == config.LinkStyle.wiki or link_style == nil then
    return Obsidian.opts.wiki_link_func(new_opts)
  else
    error(string.format("Invalid link style '%s'", link_style))
  end
end

---Return the full link under cursror
---
---@return string? link
---@return obsidian.search.RefTypes? link_type
M.cursor_link = function()
  local line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = cur_col + 1 -- 0-indexed column to 1-indexed lua string position

  local refs = search.find_refs(line, { include_naked_urls = true, include_file_urls = true, include_block_ids = true })

  local match = iter(refs):find(function(match)
    local open, close = unpack(match)
    return cur_col >= open and cur_col <= close
  end)
  if match then
    return line:sub(match[1], match[2]), match[3]
  end
end

---Get the tag under the cursor, if there is one.
---@return string?
M.cursor_tag = function()
  local current_line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for match in iter(search.find_tags(current_line)) do
    local open, close, _ = unpack(match)
    if open <= cur_col and cur_col <= close then
      return string.sub(current_line, open + 1, close)
    end
  end

  return nil
end

--- Get the heading under the cursor, if there is one.
---@return { header: string, level: integer, anchor: string }|?
M.cursor_heading = function()
  return util.parse_header(vim.api.nvim_get_current_line())
end

------------------
--- buffer api ---
------------------

--- Check if a buffer is empty.
---
---@param bufnr integer|?
---
---@return boolean
M.buffer_is_empty = function(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_line_count(bufnr) > 1 then
    return false
  else
    local first_text = vim.api.nvim_buf_get_text(bufnr, 0, 0, 0, 0, {})
    if vim.tbl_isempty(first_text) or first_text[1] == "" then
      return true
    else
      return false
    end
  end
end

--- Open a buffer for the corresponding path.
---
---@param path string|obsidian.Path
---@param opts { line: integer|?, col: integer|?, cmd: string|? }|?
---@return integer bufnr
M.open_buffer = function(path, opts)
  path = Path.new(path):resolve()
  opts = opts and opts or {}
  local cmd = vim.trim(opts.cmd and opts.cmd or "e")

  ---@type integer|?
  local result_bufnr

  -- Check for buffer in windows and use 'drop' command if one is found.
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == tostring(path) then
      cmd = "drop"
      result_bufnr = bufnr
      break
    end
  end

  vim.cmd(string.format("%s %s", cmd, vim.fn.fnameescape(tostring(path))))
  if opts.line then
    vim.api.nvim_win_set_cursor(0, { tonumber(opts.line), opts.col and opts.col or 0 })
  end

  if not result_bufnr then
    result_bufnr = vim.api.nvim_get_current_buf()
  end

  return result_bufnr
end

----------------
--- text api ---
----------------

--- Get the current visual selection of text and exit visual mode.
---
---@param opts { strict: boolean|? }|?
---
---@return { lines: string[], selection: string, csrow: integer, cscol: integer, cerow: integer, cecol: integer }|?
M.get_visual_selection = function(opts)
  opts = opts or {}
  -- Adapted from fzf-lua:
  -- https://github.com/ibhagwan/fzf-lua/blob/6ee73fdf2a79bbd74ec56d980262e29993b46f2b/lua/fzf-lua/utils.lua#L434-L466
  -- this will exit visual mode
  -- use 'gv' to reselect the text
  local _, csrow, cscol, cerow, cecol
  local mode = vim.fn.mode()
  if opts.strict and not vim.endswith(string.lower(mode), "v") then
    return
  end

  if mode == "v" or mode == "V" or mode == "" then
    -- if we are in visual mode use the live position
    _, csrow, cscol, _ = unpack(vim.fn.getpos ".")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "v")
    if mode == "V" then
      -- visual line doesn't provide columns
      cscol, cecol = 0, 999
    end
    -- exit visual mode
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
  else
    -- otherwise, use the last known visual position
    _, csrow, cscol, _ = unpack(vim.fn.getpos "'<")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "'>")
  end

  -- Swap vars if needed
  if cerow < csrow then
    csrow, cerow = cerow, csrow
    cscol, cecol = cecol, cscol
  elseif cerow == csrow and cecol < cscol then
    cscol, cecol = cecol, cscol
  end

  local lines = vim.fn.getline(csrow, cerow)
  assert(type(lines) == "table")
  if vim.tbl_isempty(lines) then
    return
  end

  -- When the whole line is selected via visual line mode ("V"), cscol / cecol will be equal to "v:maxcol"
  -- for some odd reason. So change that to what they should be here. See ':h getpos' for more info.
  local maxcol = vim.api.nvim_get_vvar "maxcol"
  if cscol == maxcol then
    cscol = string.len(lines[1])
  end
  if cecol == maxcol then
    cecol = string.len(lines[#lines])
  end

  ---@type string
  local selection
  local n = #lines
  if n <= 0 then
    selection = ""
  elseif n == 1 then
    selection = string.sub(lines[1], cscol, cecol)
  elseif n == 2 then
    selection = string.sub(lines[1], cscol) .. "\n" .. string.sub(lines[n], 1, cecol)
  else
    selection = string.sub(lines[1], cscol)
      .. "\n"
      .. table.concat(lines, "\n", 2, n - 1)
      .. "\n"
      .. string.sub(lines[n], 1, cecol)
  end

  return {
    lines = lines,
    selection = selection,
    csrow = csrow,
    cscol = cscol,
    cerow = cerow,
    cecol = cecol,
  }
end

------------------
--- UI helpers ---
------------------

---Get the strategy for opening notes
---
---@param opt obsidian.config.OpenStrategy
---@return string
M.get_open_strategy = function(opt)
  local OpenStrategy = require("obsidian.config").OpenStrategy

  -- either 'leaf', 'row' for vertically split windows, or 'col' for horizontally split windows
  local cur_layout = vim.fn.winlayout()[1]

  if vim.startswith(OpenStrategy.hsplit, opt) then
    if cur_layout ~= "col" then
      return "split "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit, opt) then
    if cur_layout ~= "row" then
      return "vsplit "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit_force, opt) then
    return "vsplit "
  elseif vim.startswith(OpenStrategy.hsplit_force, opt) then
    return "hsplit "
  elseif vim.startswith(OpenStrategy.current, opt) then
    return "e "
  else
    log.err("undefined open strategy '%s'", opt)
    return "e "
  end
end

----------------------------
--- Integration helpers ----
----------------------------

--- Get the path to where a plugin is installed.
---
---@param name string
---@return string|?
local get_src_root = function(name)
  return vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
    return vim.endswith(path, name)
  end)
end

--- Get info about a plugin.
---
---@param name string
---
---@return { commit: string|?, path: string }|?
M.get_plugin_info = function(name)
  local src_root = get_src_root(name)
  if not src_root then
    return
  end
  local out = { path = src_root }
  local obj = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = src_root }):wait(1000)
  if obj.code == 0 then
    out.commit = vim.trim(obj.stdout)
  else
    out.commit = "unknown"
  end
  return out
end

--- Get info about a external dependency.
---
---@param cmd string
---@return string|?
M.get_external_dependency_info = function(cmd)
  local obj = vim.system({ cmd, "--version" }, {}):wait(1000)
  if obj.code ~= 0 then
    return
  end
  local version = vim.version.parse(obj.stdout)
  if version then
    return ("%d.%d.%d"):format(version.major, version.minor, version.patch)
  end
end

------------------
--- UI helpers ---
------------------

local INPUT_CANCELLED = "~~~INPUT-CANCELLED~~~"

--- Prompt user for an input. Returns nil if canceled, otherwise a string (possibly empty).
---
---@param prompt string
---@param opts { completion: string|?, default: string|? }|?
---
---@return string|?
M.input = function(prompt, opts)
  opts = opts or {}

  if not vim.endswith(prompt, " ") then
    prompt = prompt .. " "
  end

  local input = vim.trim(
    vim.fn.input { prompt = prompt, completion = opts.completion, default = opts.default, cancelreturn = INPUT_CANCELLED }
  )

  if input ~= INPUT_CANCELLED then
    return input
  else
    return nil
  end
end

--- Prompt user for a confirmation.
---
---@param prompt string
---
---@return boolean
M.confirm = function(prompt)
  if not vim.endswith(util.rstrip_whitespace(prompt), "[Y/n]") then
    prompt = util.rstrip_whitespace(prompt) .. " [Y/n] "
  end

  local confirmation = M.input(prompt)
  if confirmation == nil then
    return false
  end

  confirmation = string.lower(confirmation)

  if confirmation == "" or confirmation == "y" or confirmation == "yes" then
    return true
  else
    return false
  end
end

---@enum OSType
M.OSType = {
  Linux = "Linux",
  Wsl = "Wsl",
  Windows = "Windows",
  Darwin = "Darwin",
  FreeBSD = "FreeBSD",
}

M._current_os = nil

---Get the running operating system.
---Reference https://vi.stackexchange.com/a/2577/33116
---@return OSType
M.get_os = function()
  if M._current_os ~= nil then
    return M._current_os
  end

  local this_os
  if vim.fn.has "win32" == 1 then
    this_os = M.OSType.Windows
  else
    local sysname = vim.uv.os_uname().sysname
    local release = vim.uv.os_uname().release:lower()
    if sysname:lower() == "linux" and string.find(release, "microsoft") then
      this_os = M.OSType.Wsl
    else
      this_os = sysname
    end
  end

  assert(this_os)
  M._current_os = this_os
  return this_os
end

--- Get a nice icon for a file or URL, if possible.
---
---@param path string
---
---@return string|?, string|? (icon, hl_group) The icon and highlight group.
M.get_icon = function(path)
  if util.is_url(path) then
    local icon = ""
    local _, hl_group = M.get_icon "blah.html"
    return icon, hl_group
  elseif Path.new(path):is_dir() then
    return "󰉋"
  else
    local ok, res = pcall(function()
      local icon, hl_group = require("nvim-web-devicons").get_icon(path, nil, { default = true })
      return { icon, hl_group }
    end)
    if ok and type(res) == "table" then
      local icon, hlgroup = unpack(res)
      return icon, hlgroup
    elseif vim.endswith(path, ".md") then
      return ""
    end
  end
  return nil
end

--- Resolve a basename to full path inside the vault.
---
---@param src string
---@return string
M.resolve_image_path = function(src)
  local img_folder = Obsidian.opts.attachments.img_folder

  ---@cast img_folder -nil
  if vim.startswith(img_folder, ".") then
    local dirname = Path.new(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
    return tostring(dirname / img_folder / src)
  else
    return tostring(Obsidian.dir / img_folder / src)
  end
end

--- Follow a link. If the link argument is `nil` we attempt to follow a link under the cursor.
---
---@param link string
---@param opts { open_strategy: obsidian.config.OpenStrategy|? }|?
M.follow_link = function(link, opts)
  opts = opts and opts or {}
  local Note = require "obsidian.note"

  search.resolve_link_async(link, function(result)
    if not result then
      return
    end

    ---@param res obsidian.ResolveLinkResult
    local function follow_link(res)
      if res.url ~= nil then
        Obsidian.opts.follow_url_func(res.url)
        return
      end

      if util.is_img(res.location) then
        local path = Obsidian.dir / res.location
        Obsidian.opts.follow_img_func(tostring(path))
        return
      end

      if res.note ~= nil then
        -- Go to resolved note.
        return res.note:open { line = res.line, col = res.col, open_strategy = opts.open_strategy }
      end

      if res.link_type == search.RefTypes.Wiki or res.link_type == search.RefTypes.WikiWithAlias then
        -- Prompt to create a new note.
        if M.confirm("Create new note '" .. res.location .. "'?") then
          -- Create a new note.
          ---@type string|?, string[]
          local id, aliases
          if res.name == res.location then
            aliases = {}
          else
            aliases = { res.name }
            id = res.location
          end

          local note = Note.create { title = res.name, id = id, aliases = aliases }
          return note:open {
            open_strategy = opts.open_strategy,
            callback = function(bufnr)
              note:write_to_buffer { bufnr = bufnr }
            end,
          }
        else
          log.warn "Aborted"
          return
        end
      end

      return log.err("Failed to resolve file '" .. res.location .. "'")
    end

    -- if #results == 1 then
    return vim.schedule(function()
      follow_link(result)
    end)
  end, { pick = true })
end
--------------------------
---- Mapping functions ---
--------------------------

---@param direction "next" | "prev"
M.nav_link = function(direction)
  vim.validate("direction", direction, "string", false, "nav_link must be called with a direction")
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local Note = require "obsidian.note"

  search.find_links(Note.from_buffer(0), {}, function(matches)
    if direction == "next" then
      for i = 1, #matches do
        local match = matches[i]
        if (match.line > cursor_line) or (cursor_line == match.line and cursor_col < match.start) then
          return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
        end
      end
    end

    if direction == "prev" then
      for i = #matches, 1, -1 do
        local match = matches[i]
        if (match.line < cursor_line) or (cursor_line == match.line and cursor_col > match.start) then
          return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
        end
      end
    end
  end)
end

M.smart_action = function()
  local legacy = Obsidian.opts.legacy_commands
  -- follow link if possible
  if M.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  end

  -- show notes with tag if possible
  if M.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  end

  if M.cursor_heading() then
    return "za"
  end

  -- toggle task if possible
  -- cycles through your custom UI checkboxes, default: [ ] [~] [>] [x]
  return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
end

return M
