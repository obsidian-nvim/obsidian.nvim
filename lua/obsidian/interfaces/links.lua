local actions = require "obsidian.actions"
local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.interfaces.util"
local preview = require "obsidian.preview"
local link = require "obsidian.link"
local refs = require "obsidian.parse.refs"
local uri = require "obsidian.uri"
local picker_util = require "obsidian.picker.util"

local M = {}

local function append(lines, more)
  vim.list_extend(lines, more)
end

local function note_target_range(note, anchor, block)
  local section
  local line
  if block then
    local resolved = note:resolve_block(block)
    section = resolved and resolved.section
    line = section and (section.range.start_row + 1) or (resolved and resolved.line)
  elseif anchor then
    local anchor_link = vim.startswith(anchor, "#") and anchor or ("#" .. anchor)
    local resolved = note:resolve_anchor_link(anchor_link)
    section = resolved and resolved.section
    line = section and (section.range.start_row + 1) or (resolved and resolved.line)
  end
  return section and section.range or nil, line
end

local function preview_link(match, context)
  local reference = refs.parse(match.link)
  local is_uri, scheme = false, nil
  if reference then
    is_uri, scheme = uri.is_uri(reference.target)
  end
  if reference and is_uri and scheme ~= "file" then
    return preview.url {
      url = reference.target,
      bufnr = context.bufnr,
      source_path = match.path,
      workspace_dir = context.workspace_dir,
    }
  end

  local source_path = match.path
  local source_line = vim.api.nvim_buf_get_lines(context.bufnr, match.line - 1, match.line, false)[1] or ""
  local spec = preview.text({
    "Source: " .. source_path .. ":" .. match.line,
    source_line,
    "",
    "Resolving link target…",
  }, "markdown")
  spec.pos = { 2, match.start }

  link.resolve_target_async(match.link, {
    bufnr = context.bufnr,
    source_path = source_path,
    workspace_dir = context.workspace_dir,
  }, function(target)
    if not preview.is_current(spec) then
      return
    end

    local lines = {
      "Source: " .. source_path .. ":" .. match.line,
      source_line,
      "",
    }
    local pos
    local pos_end
    local filetype = "markdown"

    if target.kind == "note" and target.notes and target.notes[1] then
      local note = target.notes[1]
      local path = tostring(note.path)
      local range, lnum = note_target_range(note, target.anchor, target.block)
      append(lines, { "Target: " .. path, "" })
      local target_lines, target_filetype = preview.read_path(path)
      local prefix = #lines
      append(lines, target_lines)
      filetype = target_filetype or "markdown"
      if range then
        pos = { prefix + range.start_row + 1, range.start_col }
        pos_end = { prefix + range.end_row + 1, range.end_col }
      elseif lnum then
        pos = { prefix + lnum, 0 }
      else
        pos = { prefix + 1, 0 }
      end
    elseif target.kind == "ambiguous" then
      append(lines, { ("Ambiguous link target (%d notes):"):format(#target.notes) })
      for _, note in ipairs(target.notes) do
        lines[#lines + 1] = "- " .. note:display_name() .. " — " .. tostring(note.path)
      end
      pos = { 4, 0 }
    elseif target.kind == "file" and target.path then
      append(lines, { "Target: " .. target.path, "" })
      local target_lines, target_filetype = preview.read_path(target.path)
      local prefix = #lines
      append(lines, target_lines)
      filetype = target_filetype or "markdown"
      pos = { prefix + 1, 0 }
    else
      append(lines, { "Missing link target" })
      if target.path then
        lines[#lines + 1] = "Expected path: " .. target.path
      end
      pos = { 4, 0 }
    end

    preview.update(spec, lines, filetype, pos, pos_end)
  end)

  return spec
end

---Select unique link occurrences from the captured current note.
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(matches: obsidian.LinkMatch[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local note = api.current_note(context.bufnr)
  if not note then
    return log.info "not in a note"
  end
  local matches = note:links()
  for _, match in ipairs(matches) do
    match.path = tostring(note.path)
  end
  if #matches == 0 then
    return log.info "No links in current note"
  end

  local entries = vim.tbl_map(function(match)
    return {
      text = match.link,
      filename = match.path,
      lnum = match.line,
      col = match.start + 1,
      user_data = match,
    }
  end, matches)
  util.select(
    entries,
    {
      prompt = "Links",
      allow_multiple = true,
      format_item = function(entry)
        return entry.text
      end,
      preview_item = function(entry)
        return preview_link(entry.user_data, context)
      end,
      selection_mappings = {
        ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Links" },
      },
    },
    opts.picker,
    function(choices)
      on_choice(vim.tbl_map(function(entry)
        return entry.user_data
      end, choices))
    end
  )
end

---Default browsing wrapper; selection follows the chosen reference.
---@param bufnr integer|?
---@param opts { winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
M.open = function(bufnr, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { bufnr = bufnr or (opts and opts.bufnr) })
  local context = util.capture_context(opts)
  return M.pick(opts, function(choices)
    if not util.context_is_valid(context) then
      return
    end
    if #choices > 1 then
      local entries = vim.tbl_map(function(match)
        return {
          filename = match.path,
          lnum = match.line,
          col = match.start + 1,
          text = match.link,
          user_data = match,
        }
      end, choices)
      return vim.api.nvim_win_call(context.winid, function()
        picker_util.send_to_qf(entries, { title = "Links" })
      end)
    end
    local match = choices[1]
    vim.api.nvim_win_call(context.winid, function()
      actions.follow_link(match.link, {
        bufnr = context.bufnr,
        winid = context.winid,
        workspace_dir = context.workspace_dir,
        cursor_row = match.line,
      })
    end)
  end)
end

return M
