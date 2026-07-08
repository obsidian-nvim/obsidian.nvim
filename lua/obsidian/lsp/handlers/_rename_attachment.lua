local M = {}

local Path = require "obsidian.path"
local log = require "obsidian.log"
local util = require "obsidian.util"
local search = require "obsidian.search"
local attachment = require "obsidian.attachment"
local rename = require "obsidian.lsp.handlers._rename"

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

---@param location string
---@param bufnr integer|?
---@return string|?
local function resolve_link(location, bufnr)
  location = vim.uri_decode(vim.trim(location))
  location = util.strip_block_links(location)
  location = util.strip_anchor_links(location)
  if location == "" then
    return nil
  end

  local is_uri = util.is_uri(location)
  if is_uri or Path.new(location):is_absolute() then
    return nil
  end

  local path = tostring(Path.new(attachment.resolve_attachment_path(location, bufnr)):resolve())
  return attachment.is_attachment_path(path) and vim.uv.fs_stat(path) ~= nil and path or nil
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
        local parse_refs = require "obsidian.parse.refs"
        local edit, meta = rename.build_workspace_edit(processed_lines, {
          old_path = tostring(old_path),
          new_path = tostring(new_path),
          include_file_rename = include_file_rename,
          match_path = function(match)
            return tostring(Path.new(match.path.text):resolve { strict = true })
          end,
          match_line = function(match)
            return match.line_number
          end,
          match_text = function(match)
            return util.rstrip_whitespace(match.lines.text)
          end,
          line_edits = function(_, ctx)
            local line_edits = {}

            for _, ref in ipairs(parse_refs.extract(ctx.text)) do
              if ref.kind == "wiki" or ref.kind == "markdown" then
                local ref_start = ref.range.start_col + (ref.embed and 2 or 1)
                local ref_text = ref.embed and ref.raw:sub(2) or ref.raw
                local link_type = ref.kind == "wiki" and ref.label and "wiki_alias" or ref.kind
                local location, name = util.parse_link(ref_text)
                if location and resolve_link(location, vim.fn.bufnr(ctx.path, true)) == tostring(old_path) then
                  vim.list_extend(
                    line_edits,
                    ref_edits(ref_start, ref_text, link_type, location, name or "", old_path, new_path.name)
                  )
                end
              end
            end

            return line_edits
          end,
        })

        callback(edit, meta)
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

M.resolve_link = resolve_link

return M
