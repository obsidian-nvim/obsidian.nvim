local embed = require "obsidian.embed"
local icons = require "obsidian.icons"
local search = require "obsidian.search"
local watchfiles = require "obsidian.lsp.watchfiles"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set {
  hooks = {
    pre_case = embed.detach_all,
    post_case = embed.detach_all,
  },
}

local namespace = vim.api.nvim_create_namespace "obsidian-nvim-embeds"

---@param buf integer
---@return table[]|nil
local function virt_lines(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
  return marks[1] and marks[1][4].virt_lines or nil
end

---@param lines table[]|nil
---@return string
local function virt_text(lines)
  local text = {}
  for _, line in ipairs(lines or {}) do
    for _, chunk in ipairs(line) do
      text[#text + 1] = chunk[1]
    end
  end
  return table.concat(text)
end

T["attach renders the note body below an embed"] = function()
  local original_resolve_note = search.resolve_note
  local ok, err = pcall(function()
    search.resolve_note = function(note_id)
      eq(note_id, "target")
      return {
        {
          contents = { "---", "title: Target", "---", "**body**" },
          frontmatter_end_line = 3,
        },
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target#section|alias]]" })
    embed.attach(buf)

    eq(virt_lines(buf), {
      {
        { "▏", "NonText" },
        { "body", "@markup.strong.markdown_inline" },
      },
    })

    search.resolve_note = function()
      return {}
    end
    embed.refresh(buf)
    eq(virt_lines(buf), nil)
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
end

T["unsupported embed types render a small preview message"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[board.canvas]]" })
  embed.attach(buf)

  eq(virt_lines(buf), {
    {
      { "▏", "NonText" },
      { icons.kinds.canvas .. " ", "Comment" },
      { "Canvas previews are not supported: ", "Comment" },
      { "board.canvas", "Directory" },
    },
  })
end

T["attachment renderers can replace fallback previews"] = function()
  local rendered_context
  local unregister = embed.register_renderer("image", function(context)
    rendered_context = context
    return { { { "future image renderer", "Comment" } } }
  end)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![](picture.png)" })
  embed.attach(buf)

  eq(rendered_context.kind, "image")
  eq(rendered_context.target, "picture.png")
  eq(rendered_context.raw_target, "picture.png")
  eq(rendered_context.label, nil)
  eq(rendered_context.syntax, "markdown")
  eq(rendered_context.col, 0)
  eq(rendered_context.end_col, 16)
  eq(virt_lines(buf), { { { "future image renderer", "Comment" } } })
  unregister()
end

T["watched target changes invalidate cached note previews"] = function()
  local original_resolve_note = search.resolve_note
  local target_path = vim.fs.normalize(vim.fn.tempname() .. ".md")
  local body = "old"
  local resolve_count = 0

  local ok, err = pcall(function()
    search.resolve_note = function()
      resolve_count = resolve_count + 1
      return {
        {
          path = target_path,
          contents = { "**" .. body .. "**" },
        },
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target]]" })
    embed.attach(buf)
    eq(virt_text(virt_lines(buf)), "▏old")

    body = "new"
    embed.refresh(buf)
    eq(virt_text(virt_lines(buf)), "▏old")
    eq(resolve_count, 2)

    watchfiles.handle {
      {
        path = target_path,
        type = vim.lsp.protocol.FileChangeType.Changed,
      },
    }

    local refreshed = vim.wait(1000, function()
      return virt_text(virt_lines(buf)) == "▏new"
    end, 10)
    eq(refreshed, true)
    eq(resolve_count, 3)
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
end

return T
