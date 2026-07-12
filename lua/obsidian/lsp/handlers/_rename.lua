local M = {}

local Note = require "obsidian.note"
local Path = require "obsidian.path"
local log = require "obsidian.log"
local api = require "obsidian.api"

-- TODO: only reject same folder duplicate name
---@param name string
---@return boolean
M.validate = function(name)
  for path in api.dir(Obsidian.dir) do
    path = Path.new(path)
    if name == path.stem then
      return false
    end
    local note = Note.from_file(path)
    if note then
      if name == note.id then
        return false
      end
    end
  end
  return true
end

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

local function build_search_note(note, old_path)
  local search_note = vim.tbl_extend("force", {}, note, { path = Path.new(old_path) })
  return setmetatable(search_note, getmetatable(note))
end

---@class (private) obsidian.build_workspace_edit_opts
---@field old_path string
---@field new_path string
---@field match_path? fun(match: table): string|?
---@field match_line? fun(match: table): integer|?
---@field match_text? fun(match: table): string|?
---@field include_file_rename boolean|?
---@field line_edits fun(match: table, ctx: { path: string, line: integer, text: string }): table[]

---@param matches table[]
---@param opts obsidian.build_workspace_edit_opts
---@return lsp.WorkspaceEdit|?
---@return { count: integer, path_lookup: table<string, boolean>, buf_list: integer[], old_path: string, new_path: string }
M.build_workspace_edit = function(matches, opts)
  local count = 0
  local path_lookup = {}
  local buf_list = {}
  local documentChanges = {}
  local processed_lines = {}

  for _, match in ipairs(matches) do
    local match_path = opts.match_path and opts.match_path(match) or tostring(match.path)
    local line = opts.match_line and opts.match_line(match) or match.line
    local text = opts.match_text and opts.match_text(match) or match.text
    local line_key = match_path .. ":" .. line

    if not processed_lines[line_key] then
      processed_lines[line_key] = true

      local line_edits = opts.line_edits(match, { path = match_path, line = line, text = text }) or {}
      table.sort(line_edits, function(a, b)
        return a.start_1idx > b.start_1idx
      end)

      if #line_edits > 0 then
        local edits_for_line = {}
        for _, edit_info in ipairs(line_edits) do
          edits_for_line[#edits_for_line + 1] = {
            range = {
              start = { line = line - 1, character = edit_info.start_1idx - 1 },
              ["end"] = { line = line - 1, character = edit_info.end_1idx },
            },
            newText = edit_info.new_text,
          }
          count = count + 1
        end

        documentChanges[#documentChanges + 1] = {
          textDocument = {
            uri = vim.uri_from_fname(match_path),
            version = has_nvim_0_12 and vim.NIL or nil,
          },
          edits = edits_for_line,
        }

        buf_list[#buf_list + 1] = vim.fn.bufnr(match_path, true)
        path_lookup[match_path] = true
      end
    end
  end

  if opts.include_file_rename ~= false and opts.old_path ~= opts.new_path then
    documentChanges[#documentChanges + 1] = {
      kind = "rename",
      oldUri = vim.uri_from_fname(opts.old_path),
      newUri = vim.uri_from_fname(opts.new_path),
      options = {},
    }
  end

  local edit = #documentChanges > 0 and { documentChanges = documentChanges } or nil

  return edit,
    {
      count = count,
      path_lookup = path_lookup,
      buf_list = buf_list,
      old_path = opts.old_path,
      new_path = opts.new_path,
    }
end

---@param note obsidian.Note
---@param new_name string
---@param opts? { old_path: string|?, new_path: string|?, include_file_rename: boolean|? }
---@param callback fun(edit: lsp.WorkspaceEdit|?, meta: { count: integer, path_lookup: table<string, boolean>, buf_list: integer[], old_path: string, new_path: string })
M.build_edit = function(note, new_name, opts, callback)
  opts = opts or {}

  local old_path = opts.old_path or tostring(note.path)
  local new_path = opts.new_path or (vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md")
  local include_file_rename = opts.include_file_rename ~= false
  local search_note = build_search_note(note, old_path)
  local old_refs = search_note:get_reference_paths()
  -- Pre-compute url-encoded refs for backlink search so backlinks() doesn't repeat get_reference_paths()
  local search_refs = search_note:get_reference_paths { urlencode = true }

  -- Sort refs by length (longest first) to match most specific reference first
  table.sort(old_refs, function(a, b)
    return #a > #b
  end)

  search_note:backlinks_async({ refs = search_refs }, function(matches)
    local edit, meta = M.build_workspace_edit(matches, {
      old_path = old_path,
      new_path = new_path,
      include_file_rename = include_file_rename,
      line_edits = function(match)
        local line_edits = {}

        for _, ref in ipairs(old_refs) do
          local search_start = 1
          while true do
            local offset_st, offset_ed = string.find(match.text, ref, search_start, true)
            if not offset_st then
              break
            end

            local new_text = new_name
            if vim.endswith(ref, ".md") then
              new_text = new_name .. ".md"
            end

            -- Check if this position overlaps with an already found edit (longer ref takes priority)
            local dominated = false
            for _, existing in ipairs(line_edits) do
              if offset_st >= existing.start_1idx and offset_ed <= existing.end_1idx then
                -- This match is inside an existing longer match, skip it
                dominated = true
                break
              end
            end

            if not dominated then
              line_edits[#line_edits + 1] = {
                start_1idx = offset_st,
                end_1idx = offset_ed,
                new_text = new_text,
              }
            end

            ---@cast offset_ed -nil
            search_start = offset_ed + 1
          end
        end

        return line_edits
      end,
    })

    callback(edit, meta)
  end)
end

---@param note obsidian.Note
---@param new_name string
---@param callback function -- TODO:
---@param opts? { old_path: string|?, new_path: string|?, include_file_rename: boolean|? }
M.rename = function(note, new_name, callback, opts)
  opts = opts or {}

  M.build_edit(note, new_name, opts, function(edit, meta)
    -- Deliver the WorkspaceEdit immediately so the client applies it first.
    callback(nil, edit)

    -- Defer the post-rename buffer cleanup to a main-loop schedule so it runs
    -- after the client has applied the edit (including the file rename).
    vim.schedule(function()
      local current_file = vim.api.nvim_buf_get_name(0)
      local new_path = meta.new_path
      local old_path = meta.old_path
      local buf_list = meta.buf_list

      if not note.bufnr then
        note.bufnr = vim.fn.bufnr(new_path, true)
      end

      -- so that file with renamed refs are displaying correctly
      for _, buf in ipairs(buf_list) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].filetype = "markdown"
        end
      end

      note.id = new_name
      note.path = Path.new(new_path)
      note:save_to_buffer { bufnr = note.bufnr }

      vim.cmd "silent! wall"
      if current_file == old_path then
        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
      else
        vim.cmd("edit " .. vim.fn.fnameescape(current_file))
      end

      require("obsidian.lsp").start(vim.api.nvim_get_current_buf())

      log.info("renamed " .. meta.count .. " reference(s) across " .. vim.tbl_count(meta.path_lookup) .. " file(s)")
    end)
  end)
end

return M
