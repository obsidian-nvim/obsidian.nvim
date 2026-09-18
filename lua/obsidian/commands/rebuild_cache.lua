local cache = require "obsidian.cache"
local log = require "obsidian.log"

return function()
  if not cache.is_enabled() then
    return log.warn "Cache is disabled"
  end

  local old_count = cache.notes.count()
  cache.notes.reindex()
  cache.notes.flush()
  log.info("Rebuilt cache: %d -> %d note(s)", old_count, cache.notes.count())
end
