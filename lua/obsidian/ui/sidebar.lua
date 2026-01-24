local NuiTree = require "nui.tree"

local state = {}

local function create_split()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    split = "left",
  })
  return { buf = buf, win = win }
end

local function spwan_sidebar(nodes)
  state = create_split()

  local tree = NuiTree {
    bufnr = state.buf,
    nodes = nodes,
  }

  tree:render()

  local map_options = { noremap = true, nowait = true, buffer = state.buf }

  vim.keymap.set("n", "<tab>", function()
    local node = tree:get_node()

    if node:is_expanded() then
      if node:collapse() then
        tree:render()
      end
    else
      if node:expand() then
        tree:render()
      end
    end
  end, map_options)
end

---@param tag_locations obsidian.TagLocation[]
---@return string[]
local list_tags = function(tag_locations)
  local tags = {}
  for _, tag_loc in ipairs(tag_locations) do
    local tag = tag_loc.tag
    if not tags[tag] then
      tags[tag] = 1
    else
      tags[tag] = tags[tag] + 1
    end
  end
  return tags
end

-- local log = require "obsidian.log"
-- local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"

local function tags_view()
  local workspace = api.find_workspace(vim.api.nvim_buf_get_name(0)) or Obsidian.workspace
  local dir = workspace.root

  search.find_tags_async("", function(tag_locations)
    local tags = list_tags(tag_locations)
    vim.print(tags) -- TODO: handle nested tags
  end, { dir = dir })

  -- spwan_sidebar {
  --   NuiTree.Node { text = "a" },
  --   NuiTree.Node({ text = "b" }, {
  --     NuiTree.Node { text = "b-1" },
  --     NuiTree.Node { text = { "b-2", "b-3" } },
  --   }),
  -- }
end

tags_view()
