return function(data)
  Obsidian.picker.find_files {
    prompt_title = "Quick Switch",
    dir = Obsidian.dir,
    query = data and data.args ~= "" and data.args or nil,
  }
end
