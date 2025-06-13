-- What would be required to use pickeme.lua instead of our custom picker abstraction?
--
-- - [x] custom actions
-- - [ ] access to the query string
-- - [ ] support for mini.picker
-- - rewrite our picker logic to dispatch to pickme
-------------------------------------------------------------------
local pickme = require "pickme"
local iter = require("obsidian.itertools").iter
local search = require "obsidian.search"

-------------------------------------------------------------------
-- Helpers
local function iter2array(iterable)
  local matches = {}
  for match in iter(iterable) do
    table.insert(matches, match)
  end
  return matches
end

-------------------------------------------------------------------
-- Action handlers for pickme

---@param bufnr number|nil
---@param selection table
local function insert_link(bufnr, selection)
  local link = selection.value
  vim.api.nvim_put({ link }, "", false, true)
  -- TODO: update UI
end

---@param bufnr number|nil
---@param selection table
local function create_note(bufnr, selection)
  vim.notify("TODO Creating note: " .. selection.value .. ". Missing the query string.")
  vim.print(bufnr)
  vim.print(selection)
end

local mappings = {
  ["<C-l>"] = { func = insert_link, name = "intert link" },
  ["<C-x>"] = { func = create_note, name = "create note" },
}
local _action_map_pickme = {}
for key, val in pairs(mappings) do
  _action_map_pickme[key] = val.func
end

-------------------------------------------------------------------
---@param heading string
---@param mappings table
local function gen_title(heading, mappings)
  local title = { heading }
  for key, mapping in pairs(mappings) do
    table.insert(title, key .. " " .. mapping.name)
  end
  return table.concat(title, " | ")
end

-------------------------------------------------------------------
vim.keymap.set("n", ",,", function()
  -- use various seach options from obsidian here
  local search_results = search.find(".", "")
  local items = iter2array(search_results)

  pickme.custom_picker {
    -- picker_override = "telescope",
    picker_override = "fzf-lua",
    --
    title = gen_title("Notes", mappings),
    items = items,
    entry_maker = function(item)
      return { display = item, value = item }
    end,
    preview_generator = function(item)
      local file = io.open(item, "r")
      if file then
        local content = file:read "*a"
        file:close()
        return content
      else
        return "Unable to open file: `" .. item .. "`"
      end
    end,
    preview_ft = "markdown",
    -- <CR> default action
    selection_handler = function(_, selection)
      print("# Selected: " .. selection.value)
    end,
    action_map = _action_map_pickme,
  }
end)
