local system = {}

system.clipboard = function() end

system.prompt = function() end
system.suggester = function() end

local date = {}

date.now = function(format, offset, reference, reference_format)
  return os.date(format, offset)
  -- TODO: moment.js
end

date.tommorrow = function() end
date.weekday = function() end
date.yesterday = function() end

return {
  app = {},
  config = {},
  date = date,
  file = {},
  frontmatter = {},
  hooks = {},
  obsidian = {},
  system = system,
  web = {},
}
