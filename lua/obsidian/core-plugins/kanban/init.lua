--- Minimal browser Kanban view for Obsidian Kanban markdown boards.
---
--- Supports the common obsidian-kanban format:
---   ---
---   kanban-plugin: board
---   ---
---   ## Column
---   - [ ] Card text
---   - [x] Done card

local Path = require "obsidian.path"
local HttpServer = require "obsidian.web.server"

local uv = vim.uv

local M = {}

local COLUMN_LEVEL = 2

---@class obsidian.kanban.Card
---@field id string
---@field text string
---@field checked boolean
---@field lines string[]

---@class obsidian.kanban.Column
---@field id string
---@field title string
---@field heading string
---@field leading_lines string[]
---@field cards obsidian.kanban.Card[]

---@class obsidian.kanban.Board
---@field path string|nil
---@field title string
---@field prefix string[]
---@field columns obsidian.kanban.Column[]
---@field suffix string[]
---@field is_kanban boolean

---@param line string
---@return string? title
local function parse_column_heading(line)
  local hashes, title = line:match "^(##)%s+(.+)%s*$"
  if hashes and #hashes == COLUMN_LEVEL then
    return vim.trim(title)
  end
end

---@param line string
---@return boolean? checked
---@return string? text
local function parse_card_line(line)
  local mark, text = line:match "^[-*+]%s+%[([ xX%-])%]%s*(.*)$"
  if not mark then
    return nil, nil
  end
  return mark:lower() == "x", text or ""
end

---@param text string
---@return string
local function make_card_line(text)
  return "- [ ] " .. text
end

---@param path string
---@return string
local function title_from_path(path)
  local base = path:gsub("\\", "/"):match "([^/]+)$" or path
  return (base:gsub("%.[^.]*$", ""))
end

---@param path string
---@return string[]? lines
---@return string? err
local function read_file_lines(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err
  end

  local content = file:read "*a" or ""
  file:close()
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")

  local lines = {}
  local pos = 1
  while pos <= #content do
    local nl = content:find("\n", pos, true)
    if not nl then
      lines[#lines + 1] = content:sub(pos)
      break
    end

    lines[#lines + 1] = content:sub(pos, nl - 1)
    pos = nl + 1
  end

  return lines, nil
end

---@param path string
---@param lines string[]
---@return boolean success
---@return string? err
local function write_file_lines(path, lines)
  local file, err = io.open(path, "wb")
  if not file then
    return false, err
  end

  if #lines > 0 then
    file:write(table.concat(lines, "\n"))
    file:write "\n"
  end

  file:close()
  return true, nil
end

---@param lines string[]
---@return boolean
local function has_kanban_frontmatter(lines)
  if lines[1] ~= "---" then
    return false
  end

  for i = 2, #lines do
    if lines[i]:match "^%-%-%-+$" then
      return false
    end
    if lines[i]:match "^kanban%-plugin:%s*board%s*$" then
      return true
    end
  end

  return false
end

---@param board obsidian.kanban.Board
local function assign_ids(board)
  for col_idx, column in ipairs(board.columns) do
    column.id = "col:" .. col_idx
    for card_idx, card in ipairs(column.cards) do
      card.id = "card:" .. col_idx .. ":" .. card_idx
    end
  end
end

---@param lines string[]
---@param opts { path: string|nil, title: string|nil }|nil
---@return obsidian.kanban.Board
function M.parse_lines(lines, opts)
  opts = opts or {}
  local board = {
    path = opts.path,
    title = opts.title or (opts.path and title_from_path(opts.path)) or "Kanban",
    prefix = {},
    columns = {},
    suffix = {},
    is_kanban = has_kanban_frontmatter(lines),
  }

  ---@type obsidian.kanban.Column|nil
  local column = nil
  ---@type obsidian.kanban.Card|nil
  local card = nil
  local in_suffix = false

  local function close_card()
    if card and column then
      local _, text = parse_card_line(card.lines[1] or "")
      card.text = text or ""
      column.cards[#column.cards + 1] = card
    end
    card = nil
  end

  local function close_column()
    close_card()
    column = nil
  end

  local function move_trailing_blank_lines_to_suffix()
    local source = card and card.lines or (column and column.leading_lines) or board.prefix
    while source and source[#source] == "" do
      table.insert(board.suffix, 1, table.remove(source))
    end
  end

  for _, line in ipairs(lines) do
    local title = parse_column_heading(line)
    if in_suffix then
      board.suffix[#board.suffix + 1] = line
    elseif line:match "^%%%%%s*kanban:settings" then
      move_trailing_blank_lines_to_suffix()
      close_card()
      board.suffix[#board.suffix + 1] = line
      in_suffix = true
    elseif title then
      close_column()
      column = {
        id = "",
        title = title,
        heading = line,
        leading_lines = {},
        cards = {},
      }
      board.columns[#board.columns + 1] = column
    elseif column then
      local checked, text = parse_card_line(line)
      if checked ~= nil then
        close_card()
        card = { id = "", text = text or "", checked = checked, lines = { line } }
      elseif card then
        card.lines[#card.lines + 1] = line
      else
        column.leading_lines[#column.leading_lines + 1] = line
      end
    else
      board.prefix[#board.prefix + 1] = line
    end
  end

  close_column()
  assign_ids(board)
  return board
end

---@param path string
---@return obsidian.kanban.Board? board
---@return string? err
function M.read_board(path)
  local lines, err = read_file_lines(path)
  if not lines then
    return nil, err or "failed to read board"
  end
  return M.parse_lines(lines, { path = path }), nil
end

---@param board obsidian.kanban.Board
---@return string[]
function M.serialize_board(board)
  local lines = vim.deepcopy(board.prefix or {})

  for col_idx, column in ipairs(board.columns or {}) do
    if #lines > 0 and lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end

    lines[#lines + 1] = column.heading ~= "" and column.heading or ("## " .. column.title)
    vim.list_extend(lines, column.leading_lines or {})

    for _, card in ipairs(column.cards or {}) do
      vim.list_extend(lines, card.lines or { make_card_line(card.text or "") })
    end

    if col_idx < #board.columns and lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end
  end

  local suffix = board.suffix or {}
  local suffix_start = lines[#lines] == "" and suffix[1] == "" and 2 or 1
  for i = suffix_start, #suffix do
    lines[#lines + 1] = suffix[i]
  end

  return lines
end

---@param path string
---@param lines string[]
---@return boolean success
---@return string? err
local function write_lines(path, lines)
  local ok, err = write_file_lines(path, lines)
  if not ok then
    return false, err or "failed to write board"
  end
  return true, nil
end

---@param board obsidian.kanban.Board
---@param path string
---@return boolean success
---@return string? err
function M.write_board(board, path)
  return write_lines(path, M.serialize_board(board))
end

---@param board obsidian.kanban.Board
---@param card_id string
---@return obsidian.kanban.Card? card
---@return integer? col_idx
---@return integer? card_idx
local function find_card(board, card_id)
  for col_idx, column in ipairs(board.columns or {}) do
    for card_idx, card in ipairs(column.cards or {}) do
      if card.id == card_id then
        return card, col_idx, card_idx
      end
    end
  end
end

---@param board obsidian.kanban.Board
---@param column_id string
---@return obsidian.kanban.Column? column
---@return integer? col_idx
local function find_column(board, column_id)
  for col_idx, column in ipairs(board.columns or {}) do
    if column.id == column_id then
      return column, col_idx
    end
  end
end

---@param board obsidian.kanban.Board
---@param card_id string
---@param to_column_id string
---@param to_index integer
---@return boolean success
---@return string? err
function M.move_card(board, card_id, to_column_id, to_index)
  local card, from_col_idx, from_card_idx = find_card(board, card_id)
  local to_column = find_column(board, to_column_id)
  if not card or not from_col_idx or not from_card_idx then
    return false, "card not found"
  end
  if not to_column then
    return false, "column not found"
  end

  table.remove(board.columns[from_col_idx].cards, from_card_idx)
  if to_column == board.columns[from_col_idx] and to_index > from_card_idx then
    to_index = to_index - 1
  end
  to_index = math.max(1, math.min(to_index, #to_column.cards + 1))
  table.insert(to_column.cards, to_index, card)
  assign_ids(board)
  return true, nil
end

---@param board obsidian.kanban.Board
---@param card_id string
---@param checked boolean
---@return boolean success
---@return string? err
function M.toggle_card(board, card_id, checked)
  local card = find_card(board, card_id)
  if not card then
    return false, "card not found"
  end

  local line = card.lines[1] or make_card_line(card.text or "")
  card.lines[1] = line:gsub("^(%s*[-*+]%s+%[)[ xX%-](%]%s*)", "%1" .. (checked and "x" or " ") .. "%2", 1)
  card.checked = checked
  return true, nil
end

---@param board obsidian.kanban.Board
---@param column_id string
---@param text string
---@return boolean success
---@return string? err
function M.add_card(board, column_id, text)
  local column = find_column(board, column_id)
  text = vim.trim(text or "")
  if not column then
    return false, "column not found"
  end
  if text == "" then
    return false, "card text is empty"
  end

  column.cards[#column.cards + 1] = { id = "", text = text, checked = false, lines = { make_card_line(text) } }
  assign_ids(board)
  return true, nil
end

---@param board obsidian.kanban.Board
---@param title string
---@return boolean success
---@return string? err
function M.add_column(board, title)
  title = vim.trim(title or "")
  if title == "" then
    return false, "column title is empty"
  end

  board.columns[#board.columns + 1] = {
    id = "",
    title = title,
    heading = "## " .. title,
    leading_lines = { "" },
    cards = {},
  }
  assign_ids(board)
  return true, nil
end

---@param board obsidian.kanban.Board
---@param column_id string
---@param title string
---@return boolean success
---@return string? err
function M.rename_column(board, column_id, title)
  local column = find_column(board, column_id)
  title = vim.trim(title or "")
  if not column then
    return false, "column not found"
  end
  if title == "" then
    return false, "column title is empty"
  end

  column.title = title
  column.heading = "## " .. title
  return true, nil
end

---@return string
local function make_token()
  return string.format("%x-%d-%s", uv.hrtime(), math.random(1000000000), tostring {})
end

---@param client uv_tcp_t
---@param status string
---@param message string
local function respond_error(client, status, message)
  HttpServer.respond(client, status, "application/json", vim.json.encode { ok = false, error = message })
end

---@param client uv_tcp_t
---@param board obsidian.kanban.Board
local function respond_board(client, board)
  HttpServer.respond_json(client, { ok = true, board = board })
end

---@return obsidian.kanban.Board? board
---@return string? err
local function current_board()
  if not M._path or M._path == "" then
    return nil, "no kanban note selected"
  end
  return M.read_board(M._path)
end

---@param path string
---@return string
local function dirname(path)
  return (path:gsub("\\", "/"):match "^(.*)/[^/]*$" or ".")
end

---@param path string
---@return string
local function normalize_path(path)
  local absolute = path:sub(1, 1) == "/"
  local out = {}
  for part in path:gsub("\\", "/"):gmatch "[^/]+" do
    if part == ".." then
      if #out > 0 then
        out[#out] = nil
      end
    elseif part ~= "." and part ~= "" then
      out[#out + 1] = part
    end
  end
  return (absolute and "/" or "") .. table.concat(out, "/")
end

---@param base string
---@param rel string
---@return string
local function join_path(base, rel)
  if rel:sub(1, 1) == "/" then
    return normalize_path(rel)
  end
  return normalize_path(base:gsub("/+$", "") .. "/" .. rel)
end

---@param path string
---@return boolean
local function is_markdown_path(path)
  return path:lower():match "%.md$" ~= nil
end

---@param path string
---@return string[]
local function note_candidates(path)
  if is_markdown_path(path) then
    return { path }
  end
  return { path, path .. ".md" }
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.trim(target or "")
  target = target:match "^%[%[(.*)%]%]$" or target
  target = target:match "^%[[^%]]+%]%((.*)%)$" or target
  target = target:match "^([^|]+)" or target
  target = target:match "^([^#]+)" or target
  target = target:gsub("^%./", "")
  local ok, decoded = pcall(vim.uri_decode, target)
  if ok then
    target = decoded
  end
  return vim.trim(target)
end

---@param root string
---@param stem string
---@return string?
local function find_note_by_stem(root, stem)
  local scan = uv.fs_scandir(root)
  if not scan then
    return nil
  end

  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then
      break
    end

    local path = join_path(root, name)
    if kind == "directory" then
      local found = find_note_by_stem(path, stem)
      if found then
        return found
      end
    elseif kind == "file" and name:lower() == (stem:lower() .. ".md") then
      return path
    end
  end
end

---@param target string
---@return string? path
---@return string? err
function M.resolve_link_target(target)
  target = normalize_link_target(target)
  if target == "" then
    return nil, "empty link target"
  end
  if target:match "^[%w+.-]+:" then
    return nil, "external link target"
  end
  if not M._path or not M._vault_dir then
    return nil, "no kanban note selected"
  end

  local candidates = {}
  local function add_candidates(path)
    for _, candidate in ipairs(note_candidates(path)) do
      candidates[#candidates + 1] = candidate
    end
  end

  if target:sub(1, 1) == "/" then
    add_candidates(join_path(M._vault_dir, target:sub(2)))
  else
    add_candidates(join_path(dirname(M._path), target))
    add_candidates(join_path(M._vault_dir, target))
  end

  for _, candidate in ipairs(candidates) do
    local stat = uv.fs_stat(candidate)
    if stat and stat.type == "file" then
      return candidate, nil
    end
  end

  if not target:find "/" and not is_markdown_path(target) then
    local found = find_note_by_stem(M._vault_dir, target)
    if found then
      return found, nil
    end
  end

  return nil, "note not found: " .. target
end

---@param target string
---@return boolean success
---@return string? err
function M.open_link_target(target)
  local path, err = M.resolve_link_target(target)
  if not path then
    return false, err
  end

  vim.schedule(function()
    require("obsidian.api").open_note({ filename = path }, "edit")
  end)
  return true, nil
end

---@param req obsidian.web.Request
---@return table? payload
---@return string? err
local function decode_payload(req)
  local ok, payload = pcall(vim.json.decode, req.body or "")
  if not ok or type(payload) ~= "table" then
    return nil, "invalid JSON"
  end
  return payload, nil
end

---@param client uv_tcp_t
---@param fn fun(board: obsidian.kanban.Board, payload: table): boolean, string?
---@param req obsidian.web.Request
local function mutate_board(client, req, fn)
  local payload, payload_err = decode_payload(req)
  if not payload then
    respond_error(client, "400 Bad Request", payload_err or "invalid JSON")
    return
  end

  local board, read_err = current_board()
  if not board then
    respond_error(client, "404 Not Found", read_err or "board not found")
    return
  end

  local success, err = fn(board, payload)
  if not success then
    respond_error(client, "400 Bad Request", err or "invalid request")
    return
  end

  success, err = M.write_board(board, M._path)
  if not success then
    respond_error(client, "409 Conflict", err or "failed to write board")
    return
  end

  local updated = M.read_board(M._path)
  respond_board(client, updated or board)
end

---@return string
local function kanban_page()
  return M._page or ""
end

---@param client uv_tcp_t
---@param req obsidian.web.Request
local function handle_request(client, req)
  if req.path == "/" and req.method == "GET" then
    HttpServer.respond(client, "200 OK", "text/html; charset=utf-8", kanban_page())
  elseif req.path == "/api/board" and req.method == "GET" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
      return
    end

    local board, err = current_board()
    if board then
      respond_board(client, board)
    else
      respond_error(client, "404 Not Found", err or "board not found")
    end
  elseif req.path == "/api/move" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      mutate_board(client, req, function(board, payload)
        return M.move_card(board, payload.card_id, payload.to_column_id, tonumber(payload.to_index) or 1)
      end)
    end
  elseif req.path == "/api/toggle" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      mutate_board(client, req, function(board, payload)
        return M.toggle_card(board, payload.card_id, payload.checked == true)
      end)
    end
  elseif req.path == "/api/add-card" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      mutate_board(client, req, function(board, payload)
        return M.add_card(board, payload.column_id, payload.text)
      end)
    end
  elseif req.path == "/api/add-column" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      mutate_board(client, req, function(board, payload)
        return M.add_column(board, payload.title)
      end)
    end
  elseif req.path == "/api/rename-column" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      mutate_board(client, req, function(board, payload)
        return M.rename_column(board, payload.column_id, payload.title)
      end)
    end
  elseif req.path == "/api/open-link" and req.method == "POST" then
    if req.params.token ~= M._token then
      HttpServer.respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      local payload, payload_err = decode_payload(req)
      if not payload then
        respond_error(client, "400 Bad Request", payload_err or "invalid JSON")
        return
      end

      local success, err = M.open_link_target(payload.target)
      if success then
        HttpServer.respond_json(client, { ok = true })
      else
        respond_error(client, "404 Not Found", err or "note not found")
      end
    end
  elseif req.method ~= "GET" and req.method ~= "POST" then
    HttpServer.respond(client, "405 Method Not Allowed", "text/plain", "Method not allowed")
  else
    HttpServer.respond(client, "404 Not Found", "text/plain", "Not found")
  end
end

--- Start the kanban HTTP server on the given port.
---@param port integer
---@return boolean success
function M.start_server(port)
  local server = HttpServer.new {
    port = port,
    on_error = function(err)
      vim.notify("Kanban server error: " .. tostring(err), vim.log.levels.ERROR)
    end,
    on_request = function(_, client, req)
      handle_request(client, req)
    end,
  }

  if not server:start() then
    return false
  end

  M._server = server
  M._port = server.port
  M._token = make_token()
  M._page = (require "obsidian.core-plugins.kanban.web"):gsub("__OBSIDIAN_KANBAN_TOKEN__", M._token)
  return true
end

function M.stop_server()
  if M._server then
    M._server:stop()
    M._server = nil
    M._port = nil
    M._token = nil
    M._page = nil
    M._path = nil
    M._vault_dir = nil
  end
end

---@return string? path
---@return string? err
local function current_note_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil, "current buffer has no file"
  end
  if vim.bo.filetype ~= "markdown" and not path:match "%.md$" then
    return nil, "current buffer is not a markdown note"
  end

  local ok, rel = pcall(function()
    return Path.new(path):vault_relative_path { strict = true }
  end)
  if not ok or not rel then
    return nil, "current note is not inside the active vault"
  end

  return path, nil
end

---@param path string
---@return boolean
local function open_url(path)
  if M._server then
    local url = M._server:url(path)
    vim.notify("Kanban view at " .. url)
    vim.ui.open(url)
    return true
  end

  for port = 49886, 49895 do
    if M.start_server(port) then
      local url = M._server:url(path)
      vim.notify("Kanban view at " .. url)
      vim.ui.open(url)
      return true
    end
  end

  vim.notify("Failed to start kanban server (ports 49886-49895 busy)", vim.log.levels.ERROR)
  return false
end

--- Open the current note in the browser Kanban UI.
function M.open_current_note()
  local path, err = current_note_path()
  if not path then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if vim.bo.modified then
    vim.notify("Write the current note before opening Kanban", vim.log.levels.ERROR)
    return
  end

  M._path = path
  M._vault_dir = tostring(Obsidian.dir)
  open_url "/"
end

return M
