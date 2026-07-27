- [P2] Honor allow_multiple in the Mini backend — /home/n451/Plugins/
  obsidian.nvim/lua/obsidian/picker/\_mini.lua:145-149
  When Mini is configured and allow_multiple = true (for example in tag
  selection), the source defines only choose, so MiniPick's marked-item action
  uses its default behavior and MiniPick.start() still returns only the current
  item. Consequently, the callback receives one choice rather than all marked
  choices; provide a choose_marked implementation that captures the selected
  list.

- [P2] Wipe scratch buffers created for tag previews — /home/n451/Plugins/
  obsidian.nvim/lua/obsidian/actions.lua:933-937
  When browsing tag matches with Telescope, Mini, or Snacks, this function runs
  for every highlighted entry and creates a nofile buffer whose default
  bufhidden value is hide. Those backends switch away without deleting prior
  buffers, so each cursor movement leaves another full note buffer loaded for
  the session; reuse a preview buffer or set these scratch buffers to wipe when
  hidden.

- [P2] Provide a callback default for pick_note — /home/n451/Plugins/
  obsidian.nvim/lua/obsidian/picker/init.lua:323-326
  When callers use the documented optional opts argument as pick_note(notes) or
  omit opts.callback, confirming a choice calls nil and raises an error. Either
  require and validate the callback or default it to the normal note-opening
  behavior before invoking it.
