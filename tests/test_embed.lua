local actions = require "obsidian.actions"
local embed = require "obsidian.embed"
local Note = require "obsidian.note"
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
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target|alias]]" })
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

T["long previews are truncated and scroll under the cursor"] = function()
  local original_resolve_note = search.resolve_note
  local original_buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(function()
    search.resolve_note = function()
      return {
        {
          contents = {
            "one",
            "two",
            "three",
            "four",
            "five",
            "six",
            "seven",
            "eight",
            "nine",
            "ten",
            "eleven",
            "twelve",
          },
        },
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "prefix ![[target]] suffix" })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    embed.attach(buf)

    eq(virt_text(virt_lines(buf)), "▏one▏two▏three▏four▏five▏six▏seven▏eight▏nine▏ten")
    eq("<Ignore>", actions.increment())
    eq(virt_text(virt_lines(buf)), "▏two▏three▏four▏five▏six▏seven▏eight▏nine▏ten▏eleven")
    eq("<Ignore>", actions.increment())
    eq(virt_text(virt_lines(buf)), "▏three▏four▏five▏six▏seven▏eight▏nine▏ten▏eleven▏twelve")
    eq("<Ignore>", actions.increment())

    eq("<Ignore>", actions.decrement())
    eq(virt_text(virt_lines(buf)), "▏two▏three▏four▏five▏six▏seven▏eight▏nine▏ten▏eleven")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    eq("<C-x>", actions.decrement())
  end)
  search.resolve_note = original_resolve_note
  if vim.api.nvim_buf_is_valid(original_buf) then
    vim.api.nvim_set_current_buf(original_buf)
  end
  if not ok then
    error(err)
  end
end

T["increment and decrement pass native keys and counts through"] = function()
  local original_buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "value 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
    vim.keymap.set("n", "<C-a>", actions.increment, { expr = true, buffer = buf })
    vim.keymap.set("n", "<C-x>", actions.decrement, { expr = true, buffer = buf })

    local increment = vim.api.nvim_replace_termcodes("3<C-a>", true, false, true)
    vim.api.nvim_feedkeys(increment, "xt", false)
    eq("value 4", vim.api.nvim_get_current_line())

    local decrement = vim.api.nvim_replace_termcodes("2<C-x>", true, false, true)
    vim.api.nvim_feedkeys(decrement, "xt", false)
    eq("value 2", vim.api.nvim_get_current_line())
  end)
  if vim.api.nvim_buf_is_valid(original_buf) then
    vim.api.nvim_set_current_buf(original_buf)
  end
  if not ok then
    error(err)
  end
end

T["heading embeds render the full section without truncation"] = function()
  local original_resolve_note = search.resolve_note
  local ok, err = pcall(function()
    search.resolve_note = function(note_id, opts)
      eq("target", note_id)
      eq(true, opts.notes.collect_anchor_links)
      return {
        Note.from_lines({
          "# Other",
          "ignore",
          "# Selected",
          "one",
          "two",
          "three",
          "four",
          "five",
          "six",
          "seven",
          "eight",
          "nine",
          "ten",
          "eleven",
          "# Next",
          "ignore",
        }, nil, opts.notes),
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target#Selected]]" })
    embed.attach(buf)

    local lines = virt_lines(buf)
    eq(12, #lines)
    eq("▏# Selected▏one▏two▏three▏four▏five▏six▏seven▏eight▏nine▏ten▏eleven", virt_text(lines))
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
end

T["block embeds render the full block without truncation"] = function()
  local original_resolve_note = search.resolve_note
  local ok, err = pcall(function()
    search.resolve_note = function(note_id, opts)
      eq("target", note_id)
      eq(true, opts.notes.collect_blocks)
      return {
        Note.from_lines({
          "one",
          "two",
          "three",
          "four",
          "five",
          "six",
          "seven",
          "eight",
          "nine",
          "ten",
          "eleven",
          "twelve ^block",
        }, nil, opts.notes),
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target#^block]]" })
    embed.attach(buf)

    local lines = virt_lines(buf)
    eq(12, #lines)
    eq(
      "▏one▏two▏three▏four▏five▏six▏seven▏eight▏nine▏ten▏eleven▏twelve ^block",
      virt_text(lines)
    )
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
end

T["non-Markdown embeds are ignored"] = function()
  local original_resolve_note = search.resolve_note
  local resolve_count = 0
  local ok, err = pcall(function()
    search.resolve_note = function()
      resolve_count = resolve_count + 1
      return {}
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[board.canvas]]", "![](picture.png)" })
    embed.attach(buf)

    eq(virt_lines(buf), nil)
    eq(resolve_count, 0)
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
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
