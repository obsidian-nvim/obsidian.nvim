local Vault = require("obsidian.remote-vault.vault").Vault

local M = {}

local function iso_time(value)
  if type(value) ~= "number" then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", value)
end

local function get_db(configured)
  if configured then
    return configured
  end
  local ok, feed = pcall(require, "feed")
  if not ok then
    error("feed adapter requires feed.nvim: " .. tostring(feed), 0)
  end
  return feed.db
end

local function feed_title(db, entry)
  local feed = db.feeds and db.feeds[entry.feed]
  if type(feed) == "table" then
    return feed.title or feed.name or entry.feed
  end
  return entry.feed
end

local function entry_tags(db, id)
  if type(db.get_tags) ~= "function" then
    return {}
  end
  local tags = db:get_tags(id)
  if type(tags) ~= "table" or not vim.islist(tags) then
    return {}
  end
  ---@cast tags string[]
  table.sort(tags)
  return tags
end

local function revision(entry, tags)
  return vim.fn.sha256(vim.json.encode {
    title = entry.title,
    link = entry.link,
    time = entry.time,
    author = entry.author,
    feed = entry.feed,
    tags = tags,
  })
end

local function render_entry(entry, content)
  local lines = { "# " .. (entry.title or "Untitled") }
  if entry.link then
    vim.list_extend(lines, { "", entry.link })
  end
  if content and content ~= "" then
    vim.list_extend(lines, { "", content })
  end
  return lines
end

---@class obsidian.remote_vault.adapters.FeedOpts
---@field path string|obsidian.Path Absolute workspace root for this remote vault.
---@field query? string feed.nvim query defining the complete remote collection. Defaults to `+unread`.
---@field name? string
---@field removal? "archive"|"delete"|"keep"
---@field archive_dir? string
---@field db? table Inject a feed.nvim-compatible database, primarily for tests.
---@field transform? fun(content: string, entry: table): string|string[] Convert stored feed content before writing it.

---Create a remote vault backed by a feed.nvim query.
---Run `:Feed update` before syncing when fresh network data is required.
---@param opts obsidian.remote_vault.adapters.FeedOpts
---@return obsidian.remote_vault.Vault
function M.new(opts)
  vim.validate {
    path = { opts.path, { "string", "table" }, false },
    query = { opts.query, "string", true },
    name = { opts.name, "string", true },
    removal = { opts.removal, "string", true },
    archive_dir = { opts.archive_dir, "string", true },
    db = { opts.db, "table", true },
    transform = { opts.transform, "callable", true },
  }

  return Vault.new {
    name = opts.name or "rss",
    path = opts.path,
    removal = opts.removal,
    archive_dir = opts.archive_dir,
    list = function(_, callback)
      local db = get_db(opts.db)
      local ids = db:filter(opts.query or "+unread")
      if type(ids) ~= "table" or not vim.islist(ids) then
        callback "feed.nvim filter did not return an ID list"
        return
      end

      local summaries = {}
      for _, db_id in ipairs(ids) do
        local entry = db[db_id]
        if entry then
          local tags = entry_tags(db, db_id)
          summaries[#summaries + 1] = {
            id = tostring(db_id),
            revision = revision(entry, tags),
            title = entry.title,
            url = entry.link,
            added_at = iso_time(entry.time),
            updated_at = iso_time(entry.time),
            data = { db_id = db_id },
          }
        end
      end
      callback(nil, summaries)
    end,
    fetch = function(summary, _, callback)
      local db = get_db(opts.db)
      local db_id = summary.data and summary.data.db_id
      local entry = db_id and db[db_id] or nil
      if not entry then
        callback("feed.nvim entry disappeared: " .. summary.id)
        return
      end

      local ok, content = pcall(db.get, db, db_id)
      if not ok then
        callback("failed reading feed.nvim entry " .. summary.id .. ": " .. tostring(content))
        return
      end
      if opts.transform then
        content = opts.transform(content or "", entry)
      end

      local lines
      if type(content) == "table" then
        lines = { "# " .. (entry.title or "Untitled") }
        if entry.link then
          vim.list_extend(lines, { "", entry.link })
        end
        vim.list_extend(lines, { "" })
        vim.list_extend(lines, content)
      else
        lines = render_entry(entry, content)
      end

      local tags = entry_tags(db, db_id)
      callback(nil, {
        id = summary.id,
        revision = revision(entry, tags),
        title = entry.title,
        url = entry.link,
        added_at = iso_time(entry.time),
        updated_at = iso_time(entry.time),
        content = lines,
        metadata = {
          provider = "feed.nvim",
          feed = entry.feed,
          feed_title = feed_title(db, entry),
          author = entry.author,
          feed_tags = tags,
        },
      })
    end,
  }
end

return setmetatable(M, {
  __call = function(_, opts)
    return M.new(opts)
  end,
})
