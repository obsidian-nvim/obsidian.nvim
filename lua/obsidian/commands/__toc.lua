-- TODO: all pickers should do on_list callbacks

local telescope_on_list = function(data)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  pickers
    .new({}, {
      prompt_title = "Table of Contents",
      finder = finders.new_table {
        results = data.items,
        entry_maker = function(value)
          return {
            value = value,
            display = value.text,
            path = value.filename,
            ordinal = value.text,
          }
        end,
      },
    })
    :find()
end

local function mini_pick_on_list(data)
  local ok, pick = pcall(require, "mini.pick")
  if not ok then
    vim.notify("no mini.pick found", 3)
    return
  end

  local items = data.items
  for _, item in ipairs(data.items) do
    item.path = item.filename
  end

  pick.start {
    source = { items = items },
    name = "Table of Contents",
    show = pick.default_show,
    choose = pick.default_choose,
  }
end

---@param client obsidian.Client
---@param _ CommandArgs
return function(client, _)
  local picker_name = tostring(client:picker())
  if picker_name == "TelescopePicker()" then
    vim.lsp.buf.document_symbol { on_list = telescope_on_list }
  elseif picker_name == "SnacksPicker()" then
    require("snacks.picker").lsp_symbols()
  elseif picker_name == "FzfPicker()" then
    require("fzf-lua").lsp_document_symbols()
  elseif picker_name == "MiniPicker()" then
    vim.lsp.buf.document_symbol { on_list = mini_pick_on_list }
  else
    vim.lsp.buf.document_symbol { loclist = false }
  end
end
