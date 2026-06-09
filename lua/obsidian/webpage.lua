local defuddle = require "obsidian.defuddle"
local html = require "obsidian.html"
local http = require "obsidian.http"
local url = require "obsidian.url"

local M = {}

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(html:string?, err:string?)
---@return any job
M.fetch_html_async = function(page_url, opts, callback)
  return http.fetch_async(page_url, opts, function(body, err)
    callback(body, err)
  end)
end

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string?, err:string?)
---@return any job
M.fetch_html_title_async = function(page_url, opts, callback)
  return M.fetch_html_async(page_url, opts, function(body, err)
    if not body then
      callback(nil, err)
      return
    end

    local title = html.title_from_html(body)
    if not title then
      callback(nil, "html response did not include a title")
      return
    end

    callback(title, nil)
  end)
end

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string, source:"defuddle"|"html"|"url")
---@return any job
M.title_from_url_async = function(page_url, opts, callback)
  return defuddle.fetch_title_async(page_url, opts, function(title)
    if title then
      callback(title, "defuddle")
      return
    end

    M.fetch_html_title_async(page_url, opts, function(html_title)
      if html_title then
        callback(html_title, "html")
        return
      end

      callback(url.fallback_title_from_url(page_url), "url")
    end)
  end)
end

return M
