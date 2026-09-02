local M = {}

local attachment = require "obsidian.attachment"
local log = require "obsidian.log"
local Path = require "obsidian.path"
local util = require "obsidian.util"

local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1

---@class obsidian.RenameAttachmentOpts : obsidian.AttachmentResolveOpts
---@field apply? boolean Apply the workspace edit. Defaults to true.
---@field offset_encoding? "utf-8"|"utf-16"|"utf-32" LSP offset encoding. Defaults to utf-8.

---@class obsidian.RenameAttachmentMeta
---@field count integer Number of updated references.
---@field path_lookup table<string, boolean> Files containing updated references.
---@field old_path string
---@field new_path string

---@param err string
---@param callback? fun(err: string?, edit: lsp.WorkspaceEdit?, meta: obsidian.RenameAttachmentMeta?)
local function fail(err, callback)
  log.err(err)
  if callback then
    callback(err, nil, nil)
  end
end

---@param old_path obsidian.Path
---@param new_name string
---@return obsidian.Path?
---@return string? err
local function new_attachment_path(old_path, new_name)
  new_name = vim.trim(new_name)
  if new_name == "" or new_name == "." or new_name == ".." or new_name:find "[/\\]" then
    return nil, "Invalid attachment name"
  end
  if not new_name:match "%.[^./]+$" then
    new_name = new_name .. assert(old_path.suffix, "attachment has no suffix")
  end
  if not attachment.is_attachment_path(new_name) then
    return nil, "Invalid attachment name"
  end
  return assert(old_path:parent()) / new_name
end

---@param target string
---@param new_basename string
---@param kind obsidian.parse.RefKind
---@return string
local function renamed_target(target, new_basename, kind)
  local decoded = vim.uri_decode(target) or target
  local prefix = decoded:match "^(.*[/\\])" or ""
  local result = prefix .. new_basename
  if kind == "markdown" then
    return util.urlencode(result, { keep_path_sep = true })
  end
  return result
end

---@param ref obsidian.parse.Ref
---@param old_path obsidian.Path
---@param new_path obsidian.Path
---@return { start: integer, end_col: integer, new_text: string }[]
local function reference_edits(ref, old_path, new_path)
  local edits = {}
  local target = ref.target
  local old_basename = assert(old_path.name, "attachment has no basename")
  local new_basename = assert(new_path.name, "attachment has no basename")
  local target_start
  if ref.kind == "wiki" then
    local brackets = ref.raw:find("[[", 1, true)
    target_start = brackets and ref.range.start_col + brackets + 1 or nil
  elseif ref.kind == "markdown" then
    local close = ref.raw:find("](", 1, true)
    target_start = close and ref.range.start_col + close + 1 or nil
  end

  if target_start then
    edits[#edits + 1] = {
      start = target_start,
      end_col = target_start + #target,
      new_text = renamed_target(target, new_basename, ref.kind),
    }
  end

  if ref.kind == "markdown" and (ref.label == old_basename or ref.label == old_path.stem) then
    local open = ref.raw:find("[", 1, true)
    if open then
      local label_start = ref.range.start_col + open
      edits[#edits + 1] = {
        start = label_start,
        end_col = label_start + #ref.label,
        new_text = ref.label == old_path.stem and new_path.stem or new_basename,
      }
    end
  end

  return edits
end

---@param old_path obsidian.Path
---@param new_path obsidian.Path
---@param callback fun(edit: lsp.WorkspaceEdit, meta: obsidian.RenameAttachmentMeta)
local function build_edit(old_path, new_path, callback)
  local old_basename = assert(old_path.name, "attachment has no basename")
  attachment._find_async(old_basename, { filename = tostring(old_path) }, function(attachments)
    local terms = {
      old_basename,
      util.urlencode(old_basename),
      util.urlencode(old_basename, { keep_path_sep = true }),
    }
    terms = util.tbl_unique(terms)

    local matches = {}
    require("obsidian.search").search_async(
      require("obsidian.api").resolve_workspace_dir(tostring(old_path)),
      terms,
      { fixed_strings = true, ignore_case = true },
      function(match)
        matches[#matches + 1] = match
      end,
      function()
        vim.schedule(function()
          local refs = require "obsidian.parse.refs"
          local files = {}
          local file_order = {}
          local processed_lines = {}
          local count = 0

          for _, match in ipairs(matches) do
            local match_path = tostring(Path.new(match.path.text):resolve { strict = true })
            local line = match.line_number - 1
            local line_key = match_path .. ":" .. line
            if not processed_lines[line_key] then
              processed_lines[line_key] = true
              for _, ref in ipairs(refs.extract(util.rstrip_whitespace(match.lines.text))) do
                if ref.kind == "wiki" or ref.kind == "markdown" then
                  local resolved = attachment._resolve_reference(ref.target, { filename = match_path }, attachments)
                  if resolved and vim.fs.normalize(resolved) == vim.fs.normalize(tostring(old_path)) then
                    if not files[match_path] then
                      files[match_path] = {}
                      file_order[#file_order + 1] = match_path
                    end
                    for _, edit in ipairs(reference_edits(ref, old_path, new_path)) do
                      files[match_path][#files[match_path] + 1] = {
                        range = {
                          start = { line = line, character = edit.start },
                          ["end"] = { line = line, character = edit.end_col },
                        },
                        newText = edit.new_text,
                      }
                      count = count + 1
                    end
                  end
                end
              end
            end
          end

          local document_changes = {}
          local path_lookup = {}
          for _, path in ipairs(file_order) do
            table.sort(files[path], function(a, b)
              if a.range.start.line == b.range.start.line then
                return a.range.start.character > b.range.start.character
              end
              return a.range.start.line > b.range.start.line
            end)
            document_changes[#document_changes + 1] = {
              textDocument = {
                uri = vim.uri_from_fname(path),
                version = has_nvim_0_12 and vim.NIL or nil,
              },
              edits = files[path],
            }
            path_lookup[path] = true
          end

          document_changes[#document_changes + 1] = {
            kind = "rename",
            oldUri = vim.uri_from_fname(tostring(old_path)),
            newUri = vim.uri_from_fname(tostring(new_path)),
            options = {},
          }

          callback({ documentChanges = document_changes }, {
            count = count,
            path_lookup = path_lookup,
            old_path = tostring(old_path),
            new_path = tostring(new_path),
          })
        end)
      end
    )
  end)
end

--- Rename an attachment and update references that resolve to it.
---@param src string Attachment reference or path.
---@param new_name string New basename. The old extension is retained when omitted.
---@param opts obsidian.RenameAttachmentOpts|?
---@param callback? fun(err: string?, edit: lsp.WorkspaceEdit?, meta: obsidian.RenameAttachmentMeta?)
function M.rename(src, new_name, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}
  if opts.apply == false and not callback then
    return fail("callback is required when rename opts.apply is false", nil)
  end

  attachment._resolve_async(src, opts, function(path, resolve_err)
    if not path then
      return fail(resolve_err or "Failed to resolve attachment", callback)
    end

    local old_path = Path.new(path):resolve { strict = true }
    local new_path, name_err = new_attachment_path(old_path, new_name)
    if not new_path then
      return fail(name_err or "Invalid attachment name", callback)
    end
    new_path = new_path:resolve()

    if tostring(old_path) == tostring(new_path) then
      return fail("Identical attachment name", callback)
    elseif new_path:exists() then
      return fail("Attachment with same name exists", callback)
    end

    build_edit(old_path, new_path, function(edit, meta)
      if opts.apply ~= false then
        vim.lsp.util.apply_workspace_edit(edit, opts.offset_encoding or "utf-8")
        vim.cmd "silent! wall"
      end
      if callback then
        callback(nil, edit, meta)
      end
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

return M
