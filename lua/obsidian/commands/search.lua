local Ui = require "obsidian.picker.ui"

---@param data obsidian.CommandArgs
return function(data)
  Ui.search {
    dir = Obsidian.dir,
    query = data.args,
  }
end
