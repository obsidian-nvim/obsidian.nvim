local stats = require("obsidian.stats").collect {
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
}
print(require("obsidian.stats").format(stats, "markdown"))
