require("obsidian.stats").collect_async({
  include_backlinks = true,
  topics = {
    { name = "Projects", path_prefix = "projects/" },
    { name = "Books", tag = "book" },
    {
      name = "Long",
      match = function(s)
        return s.words > 2000
      end,
    },
  },
}, function(stats)
  vim.print(stats)
  -- print(require("obsidian.stats").format(stats, "markdown"))
end)
