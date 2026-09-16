local Vault = require("obsidian.remote-vault.vault").Vault

local M = {}

local list_fields = "number,title,url,updatedAt,createdAt,author,labels,assignees,state"
local view_fields = list_fields .. ",body,comments"

local function decode(output, callback)
  if not output or output.code ~= 0 then
    callback((output and output.stderr ~= "" and output.stderr) or "gh command failed")
    return
  end
  local ok, value = pcall(vim.json.decode, output.stdout or "")
  if not ok then
    callback("failed to decode gh JSON: " .. tostring(value))
    return
  end
  callback(nil, value)
end

local function default_runner(args, callback)
  if vim.fn.executable "gh" ~= 1 then
    callback "GitHub adapter requires the gh CLI"
    return
  end
  return vim.system(args, { text = true }, function(output)
    decode(output, callback)
  end)
end

local function names(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    out[#out + 1] = item.name or item.login or tostring(item)
  end
  return out
end

local function author_name(author)
  return author and (author.login or author.name) or nil
end

local function issue_id(repo, number)
  return string.format("%s#%s", repo, number)
end

local function issue_summary(repo, issue)
  return {
    id = issue_id(repo, issue.number),
    revision = issue.updatedAt,
    title = issue.title,
    url = issue.url,
    added_at = issue.createdAt,
    updated_at = issue.updatedAt,
    data = { number = issue.number },
  }
end

local function issue_body(issue)
  local lines = {
    "# " .. issue.title,
    "",
    issue.url,
  }
  if issue.body and issue.body ~= "" then
    vim.list_extend(lines, { "", issue.body })
  end
  if issue.comments and #issue.comments > 0 then
    vim.list_extend(lines, { "", "## Comments" })
    for _, comment in ipairs(issue.comments) do
      local heading = "### " .. (author_name(comment.author) or "unknown")
      if comment.createdAt then
        heading = heading .. " · " .. comment.createdAt
      end
      vim.list_extend(lines, { "", heading, "", comment.body or "" })
      if comment.url then
        vim.list_extend(lines, { "", comment.url })
      end
    end
  end
  return lines
end

---@class obsidian.remote_vault.adapters.GitHubOpts
---@field repo string Repository in OWNER/REPO or HOST/OWNER/REPO form.
---@field path string|obsidian.Path Absolute workspace root for this remote vault.
---@field name? string
---@field state? "open"|"closed"|"all"
---@field assignee? string
---@field author? string
---@field labels? string[]
---@field search? string
---@field limit? integer
---@field args? string[] Additional arguments passed to `gh issue list`.
---@field removal? "archive"|"delete"|"keep"
---@field archive_dir? string
---@field runner? fun(args: string[], callback: fun(err: string?, value: any?)) Test/custom command runner returning decoded JSON.

---Create a remote vault backed by GitHub issues.
---@param opts obsidian.remote_vault.adapters.GitHubOpts
---@return obsidian.remote_vault.Vault
function M.new(opts)
  vim.validate {
    opts = { opts, "table", false },
    repo = { opts and opts.repo, "string", false },
    path = { opts and opts.path, { "string", "table" }, false },
    labels = { opts and opts.labels, "table", true },
    args = { opts and opts.args, "table", true },
    runner = { opts and opts.runner, "callable", true },
  }
  assert(opts.repo ~= "", "GitHub adapter repo cannot be empty")

  local runner = opts.runner or function(args, callback)
    default_runner(args, callback)
  end

  return Vault.new {
    name = opts.name or "github-issues",
    path = opts.path,
    removal = opts.removal,
    archive_dir = opts.archive_dir,
    list = function(_, callback)
      local args = {
        "gh",
        "issue",
        "list",
        "--repo",
        opts.repo,
        "--state",
        opts.state or "open",
        "--limit",
        tostring(opts.limit or 100),
        "--json",
        list_fields,
      }
      if opts.assignee then
        vim.list_extend(args, { "--assignee", opts.assignee })
      end
      if opts.author then
        vim.list_extend(args, { "--author", opts.author })
      end
      for _, label in ipairs(opts.labels or {}) do
        vim.list_extend(args, { "--label", label })
      end
      if opts.search then
        vim.list_extend(args, { "--search", opts.search })
      end
      vim.list_extend(args, opts.args or {})

      return runner(args, function(err, issues)
        if err then
          callback(err)
          return
        elseif type(issues) ~= "table" or not vim.islist(issues) then
          callback "gh issue list did not return a JSON list"
          return
        end
        local summaries = {}
        for _, issue in ipairs(issues) do
          summaries[#summaries + 1] = issue_summary(opts.repo, issue)
        end
        callback(nil, summaries)
      end)
    end,
    fetch = function(summary, _, callback)
      local number = summary.data and summary.data.number
      if not number then
        callback("GitHub summary has no issue number: " .. summary.id)
        return
      end
      local args = {
        "gh",
        "issue",
        "view",
        tostring(number),
        "--repo",
        opts.repo,
        "--json",
        view_fields,
      }
      return runner(args, function(err, issue)
        if err then
          callback(err)
          return
        elseif type(issue) ~= "table" or issue.number == nil then
          callback "gh issue view did not return an issue"
          return
        end
        local resource = issue_summary(opts.repo, issue)
        resource.content = issue_body(issue)
        resource.metadata = {
          provider = "github",
          repository = opts.repo,
          issue_number = issue.number,
          issue_state = issue.state and issue.state:lower() or nil,
          author = author_name(issue.author),
          labels = names(issue.labels),
          assignees = names(issue.assignees),
        }
        callback(nil, resource)
      end)
    end,
  }
end

return setmetatable(M, {
  __call = function(_, opts)
    return M.new(opts)
  end,
})
