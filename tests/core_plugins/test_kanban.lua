local helpers = require "tests.helpers"

local T = helpers.temp_vault

T["parse_lines"] = MiniTest.new_set()

T["parse_lines"]["parses obsidian-kanban columns and cards"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local board = kanban.parse_lines {
    "---",
    "kanban-plugin: board",
    "---",
    "",
    "# Project",
    "",
    "## Backlog",
    "",
    "- [ ] Task one",
    "  - detail",
    "  - [ ] subtask belongs to task one",
    "- [x] Done task",
    "",
    "## Doing",
    "- [ ] Active",
  }

  MiniTest.expect.equality(true, board.is_kanban)
  MiniTest.expect.equality("Backlog", board.columns[1].title)
  MiniTest.expect.equality("Task one", board.columns[1].cards[1].text)
  MiniTest.expect.equality({
    "- [ ] Task one",
    "  - detail",
    "  - [ ] subtask belongs to task one",
  }, board.columns[1].cards[1].lines)
  MiniTest.expect.equality(2, #board.columns[1].cards)
  MiniTest.expect.equality(true, board.columns[1].cards[2].checked)
  MiniTest.expect.equality("Doing", board.columns[2].title)
end

T["parse_lines"]["moves cards and preserves markdown"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local board = kanban.parse_lines {
    "---",
    "kanban-plugin: board",
    "---",
    "",
    "## Todo",
    "",
    "- [ ] A",
    "  note",
    "- [ ] B",
    "",
    "## Done",
    "- [x] C",
  }

  local ok, err = kanban.move_card(board, "card:1:1", "col:2", 2)
  MiniTest.expect.equality(true, ok)
  MiniTest.expect.equality(nil, err)

  MiniTest.expect.equality({
    "---",
    "kanban-plugin: board",
    "---",
    "",
    "## Todo",
    "",
    "- [ ] B",
    "",
    "## Done",
    "- [x] C",
    "- [ ] A",
    "  note",
  }, kanban.serialize_board(board))
end

T["parse_lines"]["adds and toggles cards"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local board = kanban.parse_lines { "## Todo", "" }

  MiniTest.expect.equality(true, kanban.add_card(board, "col:1", "Ship MVP"))
  MiniTest.expect.equality(true, kanban.toggle_card(board, "card:1:1", true))
  MiniTest.expect.equality({
    "## Todo",
    "",
    "- [x] Ship MVP",
  }, kanban.serialize_board(board))
end

T["parse_lines"]["preserves obsidian-kanban settings outside cards"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local board = kanban.parse_lines {
    "## Todo",
    "- [ ] A",
    "",
    "%% kanban:settings",
    "```",
    '{"kanban-plugin":"board"}',
    "```",
    "%%",
  }

  MiniTest.expect.equality({
    "",
    "%% kanban:settings",
    "```",
    '{"kanban-plugin":"board"}',
    "```",
    "%%",
  }, board.suffix)

  MiniTest.expect.equality(true, kanban.add_column(board, "Done"))
  MiniTest.expect.equality({
    "## Todo",
    "- [ ] A",
    "",
    "## Done",
    "",
    "%% kanban:settings",
    "```",
    '{"kanban-plugin":"board"}',
    "```",
    "%%",
  }, kanban.serialize_board(board))
end

T["resolve_link_target"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local nested = Obsidian.dir / "nested"
  nested:mkdir()
  local board_path = Obsidian.dir / "Board.md"
  local target_path = nested / "Target.md"
  helpers.write("## Todo", board_path)
  helpers.write("# Target", target_path)

  kanban._path = tostring(board_path)
  kanban._vault_dir = tostring(Obsidian.dir)

  local resolved = kanban.resolve_link_target "[[Target|label]]"
  MiniTest.expect.equality(tostring(target_path), resolved)

  resolved = kanban.resolve_link_target "nested/Target#Heading"
  MiniTest.expect.equality(tostring(target_path), resolved)

  kanban._path = nil
  kanban._vault_dir = nil
end

T["read/write"] = function()
  local kanban = require "obsidian.core-plugins.kanban"
  local path = Obsidian.dir / "Board.md"
  helpers.write("## Todo\n- [ ] A", path)

  local board = assert(kanban.read_board(tostring(path)))
  MiniTest.expect.equality("Board", board.title)
  MiniTest.expect.equality(true, kanban.add_column(board, "Done"))
  MiniTest.expect.equality(true, kanban.write_board(board, tostring(path)))
  MiniTest.expect.equality({
    "## Todo",
    "- [ ] A",
    "",
    "## Done",
    "",
  }, helpers.read(path))
end

return T
