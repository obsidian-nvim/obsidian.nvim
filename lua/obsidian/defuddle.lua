local http = require "obsidian.http"
local Note = require "obsidian.note"

local M = {}

M.endpoint = "https://defuddle.md/"

---@param markdown string
---@return obsidian.Note
M.note_from_markdown = function(markdown)
  local lines = vim.split(markdown, "\n")
  return Note.from_lines(lines, nil, {})
end

---@param markdown string|nil
---@return string|nil
M.title_from_markdown = function(markdown)
  if not markdown or markdown == "" then
    return nil
  end

  return M.note_from_markdown(markdown).metadata.title
end

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(markdown:string?, err:string?)
---@return any job
M.fetch_markdown_async = function(url, opts, callback)
  return http.fetch_async(M.endpoint .. url, opts, function(markdown, err)
    callback(markdown, err)
  end)
end

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(note:obsidian.Note?, err:string?)
---@return any job
M.fetch_note_async = function(url, opts, callback)
  return M.fetch_markdown_async(url, opts, function(markdown, err)
    if not markdown then
      callback(nil, err)
      return
    end

    callback(M.note_from_markdown(markdown), nil)
  end)
end

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string?, err:string?)
---@return any job
M.fetch_title_async = function(url, opts, callback)
  return M.fetch_markdown_async(url, opts, function(markdown, err)
    if not markdown then
      callback(nil, err)
      return
    end

    local title = M.title_from_markdown(markdown)
    if not title then
      callback(nil, "defuddle response did not include a title")
      return
    end

    callback(title, nil)
  end)
end

return M
