local new_set, eq, has_error = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.error

local T = dofile("tests/helpers.lua").temp_vault
local M = require "obsidian.note"
local H = {}

local EXPECTED_LINE = "> [!IMPORTANT] INSERTED TEXT."
local EXPECTED_HEADING = "INSERTED HEADING"

T["insert_text"] = new_set()
T["insert_text"]["section nil"] = new_set()
T["insert_text"]["section found"] = new_set()
T["insert_text"]["section missing"] = new_set()
T["insert_text"]["section missing"]["create"] = new_set()
T["insert_text"]["section missing"]["error"] = new_set()
T["insert_text"]["section missing"]["cancel"] = new_set()
T["insert_text"]["section missing"]["invalid key"] = new_set()

T["insert_text"]["section nil"]["should insert at top of preamble_only"] = function()
  local note = H.save_note {
    "Body1.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = nil })

  eq(H.load_note(note), {
    EXPECTED_LINE,
    "Body1.",
  })
end

T["insert_text"]["section nil"]["should insert at bot of preamble_only"] = function()
  local note = H.save_note {
    "Body1.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = nil })

  eq(H.load_note(note), {
    "Body1.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section nil"]["should insert at top of preamble in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = nil })

  eq(H.load_note(note), {
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section nil"]["should insert at bot of preamble in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = nil })

  eq(H.load_note(note), {
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section nil"]["should insert at top of preamble in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = nil })

  eq(H.load_note(note), {
    EXPECTED_LINE,
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section nil"]["should insert at bot of preamble in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = nil })

  eq(H.load_note(note), {
    "Lorem.",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section nil"]["should replace empty content"] = function()
  local note = H.save_note {
    "# H1",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = nil })

  eq(H.load_note(note), {
    "",
    EXPECTED_LINE,
    "",
    "# H1",
  })
end

T["insert_text"]["section found"]["should insert at top of H1 in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "# H1",
    "",
    EXPECTED_LINE,
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H1 in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    EXPECTED_LINE,
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at top of H2 in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    EXPECTED_LINE,
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H2 in multi"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should insert at top of H1 in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    EXPECTED_LINE,
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H1 in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    EXPECTED_LINE,
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at top of H2 in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    EXPECTED_LINE,
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H2 in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should insert at top of H1 w/ underline in multi"] = function()
  local note = H.save_note {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "H1",
    "===",
    "",
    EXPECTED_LINE,
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H1 w/ underline in multi"] = function()
  local note = H.save_note {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "H1",
    "===",
    "",
    "Body1.",
    EXPECTED_LINE,
    "",
    "H2",
    "---",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at top of H2 w/ underline in multi"] = function()
  local note = H.save_note {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    EXPECTED_LINE,
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H2 w/ underline in multi"] = function()
  local note = H.save_note {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should insert at top of H1 w/ underline in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    EXPECTED_LINE,
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H1 w/ underline in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    EXPECTED_LINE,
    "",
    "H2",
    "---",
    "",
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at top of H2 w/ underline in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    EXPECTED_LINE,
    "Body2.",
  })
end

T["insert_text"]["section found"]["should insert at bot of H2 w/ underline in preamble_multi"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 2, header = "H2" } })

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "H1",
    "===",
    "",
    "Body1.",
    "",
    "H2",
    "---",
    "",
    "Body2.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should disregard headings within a code block"] = function()
  local note = H.save_note {
    "```markdown",
    "# H1",
    "",
    "BodyInCodeBlock.",
    "```",
    "",
    "# H1",
    "",
    "BodyOutsideCodeBlock.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "bot", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "```markdown",
    "# H1",
    "",
    "BodyInCodeBlock.",
    "```",
    "",
    "# H1",
    "",
    "BodyOutsideCodeBlock.",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should replace empty content"] = function()
  local note = H.save_note {
    "# H1",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "H1" } })

  eq(H.load_note(note), {
    "# H1",
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section found"]["should not treat fenced codeblock ticks as potential headers"] = function()
  local note = H.save_note {
    "```markdown",
    "# ```",
    "```",
    "===",
    "",
    "# ```",
    "",
    "BodyUnderTickHeader.",
  }

  note:insert_text(EXPECTED_LINE, { placement = "top", section = { level = 1, header = "```" } })

  eq(H.load_note(note), {
    "```markdown",
    "# ```",
    "```",
    "===",
    "",
    "# ```",
    "",
    EXPECTED_LINE,
    "BodyUnderTickHeader.",
  })
end

T["insert_text"]["section missing"]["create"]["should create in empty top"] = function()
  local note = H.save_note {}

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["create"]["should create in empty bot"] = function()
  local note = H.save_note {}

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["create"]["should create in preamble_only top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "Ipsum.",
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["create"]["should create in preamble_only bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "Ipsum.",
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["create"]["should create in multi top"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["create"]["should fix top padding"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" }, padding_top = true }
  )

  eq(H.load_note(note), {
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["create"]["should preserve correct padding"] = function()
  local note = H.save_note {
    "",
    "# H1",
    "",
    "Body1.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" }, padding_top = true }
  )

  eq(H.load_note(note), {
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
  })
end

T["insert_text"]["section missing"]["create"]["should create in multi bot"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["create"]["should create in preamble_multi top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["create"]["should create in preamble_multi bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "create" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
    "",
    "### " .. EXPECTED_HEADING,
    "",
    EXPECTED_LINE,
  })
end

T["insert_text"]["section missing"]["error"]["should error w/ empty top"] = function()
  local note = H.save_note {}

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ empty bot"] = function()
  local note = H.save_note {}

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ preamble_only top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ preamble_only bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ multi top"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ multi bot"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ preamble_multi top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["error"]["should error w/ preamble_multi bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "error" } }
    )
  end)
end

T["insert_text"]["section missing"]["cancel"]["should cancel in empty top"] = function()
  local note = H.save_note { "" }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), { "" })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in empty bot"] = function()
  local note = H.save_note { "" }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), { "" })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in preamble_only top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "Ipsum.",
  })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in preamble_only bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "Ipsum.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "Ipsum.",
  })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in multi top"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in multi bot"] = function()
  local note = H.save_note {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in preamble_multi top"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "top", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["cancel"]["should cancel in preamble_multi bot"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  note:insert_text(
    EXPECTED_LINE,
    { placement = "bot", section = { level = 3, header = EXPECTED_HEADING, on_missing = "cancel" } }
  )

  eq(H.load_note(note), {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  })
end

T["insert_text"]["section missing"]["invalid key"]["should error with invalid key details"] = function()
  local note = H.save_note {
    "Lorem.",
    "",
    "# H1",
    "",
    "Body1.",
    "",
    "## H2",
    "",
    "Body2.",
  }

  has_error(function()
    note:insert_text(
      EXPECTED_LINE,
      ---@diagnostic disable-next-line: assign-type-mismatch
      { placement = "top", section = { level = 1, header = EXPECTED_HEADING, on_missing = "invalid key" } }
    )
  end)
end

function H.save_note(lines)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(lines, path)
  return M.from_file(path)
end

function H.load_note(note)
  return vim.fn.readfile(tostring(note.path))
end

return T
