return {
  RgFindFiles = function(cmdarg, _cmdcomplete)
    print(cmdarg, _cmdcomplete)
    local fnames = vim.fn.systemlist 'rg --files --hidden --color=never --glob="!.git"'
    if #cmdarg == 0 then
      return fnames
    else
      return vim.fn.matchfuzzy(fnames, cmdarg)
    end
  end,
  -- attach = function(buf)
  --   if vim.fn.executable "rg" == 1 then
  --     function _G.RgFindFiles(cmdarg, _cmdcomplete)
  --       print(cmdarg, _cmdcomplete)
  --       local fnames = vim.fn.systemlist 'rg --files --hidden --color=never --glob="!.git"'
  --       if #cmdarg == 0 then
  --         return fnames
  --       else
  --         return vim.fn.matchfuzzy(fnames, cmdarg)
  --       end
  --     end
  --     vim.o.findfunc = "v:lua.RgFindFiles"
  --   end
  --
  --   local function is_cmdline_type_find()
  --     local cmdline = vim.fn.getcmdline()
  --     return vim.startswith(cmdline, "Obsidian quick_switch")
  --   end
  --
  --   vim.api.nvim_create_autocmd({ "CmdlineChanged", "CmdlineLeave" }, {
  --     pattern = { "*" },
  --     group = vim.api.nvim_create_augroup("CmdlineAutocompletion", { clear = true }),
  --     callback = function(ev)
  --       local function should_enable_autocomplete()
  --         local cmdline_cmd = vim.fn.split(vim.fn.getcmdline(), " ")[1]
  --         return is_cmdline_type_find() or cmdline_cmd == "help" or cmdline_cmd == "h"
  --       end
  --       if ev.event == "CmdlineChanged" and should_enable_autocomplete() then
  --         vim.opt.wildmode = "noselect:lastused,full"
  --         vim.fn.wildtrigger()
  --       end
  --       if ev.event == "CmdlineLeave" then
  --         vim.opt.wildmode = "full"
  --       end
  --     end,
  --   })
  -- end,
}
