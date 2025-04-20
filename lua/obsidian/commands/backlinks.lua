local log = require "obsidian.log"
local telescope_on_list = function(data)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  pickers
    .new({}, {
      prompt_title = "References",
      finder = finders.new_table {
        results = data.items,
        entry_maker = function(value)
          return {
            value = value,
            display = value.text,
            path = value.filename,
            ordinal = value.text,
            lnum = value.lnum,
          }
        end,
      },
    })
    :find()
end

---@param client obsidian.Client
return function(client)
  local picker = assert(client:picker())
  if not picker then
    log.err "No picker configured"
    return
  end
  local picker_name = tostring(picker)

  if picker_name == "TelescopePicker()" then
    vim.lsp.buf.references({
      includeDeclaration = false,
    }, { on_list = telescope_on_list })
  elseif picker_name == "SnacksPicker()" then
    require("snacks.picker").lsp_symbols()
  elseif picker_name == "FzfPicker()" then
    require("fzf-lua").lsp_document_symbols()
  elseif picker_name == "MiniPicker()" then
    -- vim.lsp.buf.document_symbol { on_list = mini_pick_on_list }
  else
    ---@type { anchor: string|?, block: string|? }
    local opts = {}
    ---@type obsidian.note.LoadOpts
    local load_opts = {}

    if ref_type == RefTypes.BlockID then
      opts.block = location
    else
      load_opts.collect_anchor_links = true
    end

    local note = client:current_note(0, load_opts)

    -- Check if cursor is on a header, if so and header parsing is enabled, use that anchor.
    if Obsidian.opts.backlinks.parse_headers then
      local header_match = util.parse_header(vim.api.nvim_get_current_line())
      if header_match then
        opts.anchor = header_match.anchor
      end
    end

    if note == nil then
      log.err "Current buffer does not appear to be a note inside the vault"
    else
      collect_backlinks(client, picker, note, opts)
    end
    vim.lsp.buf.document_symbol { loclist = false }
  end
end
