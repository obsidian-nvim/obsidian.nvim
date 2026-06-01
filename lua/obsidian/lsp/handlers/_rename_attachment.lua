local M = {}

local obsidian = require "obsidian"
local Path = obsidian.Path
local log = obsidian.log
local util = obsidian.util
local search = obsidian.search
local attachment = require "obsidian.attachment"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

---@param path string|obsidian.Path
---@return string[]
local function get_reference_paths(path)
  path = Path.new(path)
  local refs = { path.name }

  local relpath
  pcall(function()
    relpath = path:relative_to(Obsidian.dir).filename
  end)
  if relpath then
    refs[#refs + 1] = relpath
  end

  local out = {}
  for _, ref in ipairs(util.tbl_unique(refs)) do
    vim.list_extend(
      out,
      util.tbl_unique {
        ref,
        util.urlencode(ref),
        util.urlencode(ref, { keep_path_sep = true }),
      }
    )
  end
  return util.tbl_unique(out)
end

---@param refs string[]
---@return string[]
local function build_search_terms(refs)
  local terms = {}
  for _, ref in ipairs(refs) do
    terms[#terms + 1] = string.format("[[%s", ref)
    terms[#terms + 1] = string.format("](%s", ref)
    terms[#terms + 1] = string.format("](/%s", ref)
    terms[#terms + 1] = string.format("](./%s", ref)
  end
  return terms
end

---@param old_location string
---@param new_basename string
---@param link_type string
---@return string
local function new_location(old_location, new_basename, link_type)
  local location = util.strip_block_links(old_location)
  local base, _, anchor = util.strip_anchor_links(location)
  local prefix = ""
  if vim.startswith(base, "./") then
    prefix = "./"
    base = base:sub(3)
  elseif vim.startswith(base, "/") then
    prefix = "/"
    base = base:sub(2)
  end

  base = vim.uri_decode(base)
  local dir = vim.fs.dirname(base)
  local replaced = (dir and dir ~= ".") and vim.fs.joinpath(dir, new_basename) or new_basename
  if link_type == "markdown" then
    replaced = util.urlencode(replaced, { keep_path_sep = true })
  end
  return prefix .. replaced .. (anchor or "")
end

---@param ref_start integer 1-indexed
---@param ref_text string
---@param link_type "wiki"|"wiki_alias"|"markdown"
---@param location string
---@param name string
---@param old_path obsidian.Path
---@param new_basename string
---@return table[]
local function ref_edits(ref_start, ref_text, link_type, location, name, old_path, new_basename)
  local edits = {}
  local replacement = new_location(location, new_basename, link_type)

  if link_type == "wiki" then
    edits[#edits + 1] = { start_1idx = ref_start + 2, end_1idx = ref_start + #ref_text - 3, new_text = replacement }
  elseif link_type == "wiki_alias" then
    edits[#edits + 1] = { start_1idx = ref_start + 2, end_1idx = ref_start + 1 + #location, new_text = replacement }
  elseif link_type == "markdown" then
    local loc_start = ref_start + #name + 3
    edits[#edits + 1] = { start_1idx = loc_start, end_1idx = loc_start + #location - 1, new_text = replacement }

    local new_stem = Path.new(new_basename).stem
    if name == old_path.name or name == old_path.stem then
      edits[#edits + 1] = {
        start_1idx = ref_start + 1,
        end_1idx = ref_start + #name,
        new_text = name == old_path.stem and new_stem or new_basename,
      }
    end
  end

  return edits
end

---@param old_path string|obsidian.Path
---@param new_name string
---@return obsidian.Path|?
local function resolve_new_path(old_path, new_name)
  old_path = Path.new(old_path)
  new_name = vim.fs.basename(vim.trim(new_name))
  if new_name == "" then
    return nil
  end
  if not new_name:match "%.%w+$" then
    new_name = new_name .. old_path.suffix
  end
  if not attachment.is_attachment_path(new_name) then
    return nil
  end
  return assert(old_path:parent()) / new_name
end

---@param old_path string|obsidian.Path
---@param new_name string
---@param opts? { include_file_rename: boolean|? }
---@param callback fun(edit: lsp.WorkspaceEdit|?, meta: { count: integer, path_lookup: table<string, boolean>, buf_list: integer[], old_path: string, new_path: string })
M.build_edit = function(old_path, new_name, opts, callback)
  opts = opts or {}
  old_path = Path.new(old_path):resolve { strict = true }
  local new_path = resolve_new_path(old_path, new_name)
  if not new_path then
    log.info "Invalid attachment name"
    return callback(
      nil,
      { count = 0, path_lookup = {}, buf_list = {}, old_path = tostring(old_path), new_path = tostring(old_path) }
    )
  end

  new_path = new_path:resolve()
  local include_file_rename = opts.include_file_rename ~= false
  local refs = get_reference_paths(old_path)
  local processed_lines = {}

  search.search_async(
    Obsidian.dir,
    build_search_terms(refs),
    { fixed_strings = true, ignore_case = true },
    function(match)
      processed_lines[#processed_lines + 1] = match
    end,
    function()
      vim.schedule(function()
        local count = 0
        local path_lookup = {}
        local buf_list = {}
        local documentChanges = {}
        local seen_lines = {}

        for _, match in ipairs(processed_lines) do
          local match_path = tostring(Path.new(match.path.text):resolve { strict = true })
          local line_key = match_path .. ":" .. match.line_number
          if not seen_lines[line_key] then
            seen_lines[line_key] = true
            local line_text = util.rstrip_whitespace(match.lines.text)
            local line_edits = {}

            local parse_refs = require "obsidian.parse.refs"
            for _, ref in ipairs(parse_refs.extract(line_text)) do
              if ref.kind == "wiki" or ref.kind == "markdown" then
                local ref_start = ref.range.start_col + (ref.embed and 2 or 1)
                local ref_text = ref.embed and ref.raw:sub(2) or ref.raw
                local link_type = ref.kind == "wiki" and ref.label and "wiki_alias" or ref.kind
                local location, name = util.parse_link(ref_text)
                if
                  location
                  and attachment.resolve_attachment_link(location, { source_path = match_path }) == tostring(old_path)
                then
                  vim.list_extend(
                    line_edits,
                    ref_edits(ref_start, ref_text, link_type, location, name or "", old_path, new_path.name)
                  )
                end
              end
            end

            table.sort(line_edits, function(a, b)
              return a.start_1idx > b.start_1idx
            end)

            if #line_edits > 0 then
              local edits_for_line = {}
              for _, edit in ipairs(line_edits) do
                edits_for_line[#edits_for_line + 1] = {
                  range = {
                    start = { line = match.line_number - 1, character = edit.start_1idx - 1 },
                    ["end"] = { line = match.line_number - 1, character = edit.end_1idx },
                  },
                  newText = edit.new_text,
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

        if include_file_rename and tostring(old_path) ~= tostring(new_path) then
          documentChanges[#documentChanges + 1] = {
            kind = "rename",
            oldUri = vim.uri_from_fname(tostring(old_path)),
            newUri = vim.uri_from_fname(tostring(new_path)),
            options = {},
          }
        end

        callback(#documentChanges > 0 and { documentChanges = documentChanges } or nil, {
          count = count,
          path_lookup = path_lookup,
          buf_list = buf_list,
          old_path = tostring(old_path),
          new_path = tostring(new_path),
        })
      end)
    end
  )
end

---@param old_path string|obsidian.Path
---@param new_name string
---@param callback function
M.rename = function(old_path, new_name, callback)
  old_path = Path.new(old_path):resolve { strict = true }
  local new_path = resolve_new_path(old_path, new_name)
  if not new_path then
    log.info "Invalid attachment name"
    return callback(nil, {})
  end
  if tostring(old_path) == tostring(new_path:resolve()) then
    log.info "Identical name"
    return callback(nil, {})
  end
  if vim.uv.fs_stat(tostring(new_path)) then
    log.info "Attachment with same name exists"
    return callback(nil, {})
  end

  M.build_edit(old_path, new_path.name, {}, function(edit, meta)
    callback(nil, edit)
    vim.schedule(function()
      vim.cmd "silent! wall"
      log.info(
        "renamed attachment and "
          .. meta.count
          .. " reference(s) across "
          .. vim.tbl_count(meta.path_lookup)
          .. " file(s)"
      )
    end)
  end)
end

---@param location string
---@return string|?
M.resolve_link = function(location)
  return attachment.resolve_attachment_link(location)
end

return M
