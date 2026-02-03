vim.api.nvim_create_user_command("Obsidian", function(data)
  if not Obsidian then
    require("obsidian.log").err "Did not setup obsidian.nvim"
    return
  end
  local commands = require "obsidian.commands"
  if #data.fargs == 0 then
    commands.show_menu(data)
    return
  end
  commands.handle_command(data)
end, {
  nargs = "*",
  complete = function(_, cmdline, _)
    if not Obsidian then
      require("obsidian.log").err_once "Did not setup obsidian.nvim"
      return
    end
    local commands = require "obsidian.commands"
    return commands.get_completions(cmdline)
  end,
  range = 2,
})
