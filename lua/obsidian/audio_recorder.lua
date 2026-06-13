local M = {}

local attachment = require "obsidian.attachment"
local log = require "obsidian.log"
local util = require "obsidian.util"

local ns = vim.api.nvim_create_namespace "obsidian.audio_recorder"

local state = {
  recording = false,
  processing = false,
  job = nil,
  temp_path = nil,
  bufnr = nil,
  mark_id = nil,
  started_at = nil,
}

local audio_exts = {
  ["3gp"] = true,
  flac = true,
  m4a = true,
  mp3 = true,
  ogg = true,
  wav = true,
  webm = true,
}

local function opts()
  return Obsidian.opts.audio_recorder or {}
end

local function replace_file_arg(cmd, path)
  local out = {}
  for i, arg in ipairs(cmd) do
    out[i] = arg == "{file}" and path or arg
  end
  return out
end

---@return string|nil
M.available_backend = function()
  if vim.fn.executable "rec" == 1 then
    return "rec"
  elseif vim.fn.executable "sox" == 1 then
    return "sox"
  elseif vim.fn.executable "arecord" == 1 then
    return "arecord"
  end
end

local function default_record_cmd(path)
  local backend = M.available_backend()
  if backend == "rec" then
    return { "rec", "-q", "-c", "1", "-r", "16000", path }
  elseif backend == "sox" then
    return { "sox", "-q", "-d", "-c", "1", "-r", "16000", path }
  elseif backend == "arecord" then
    return { "arecord", "-q", "-f", "cd", "-t", "wav", path }
  end
  return nil, "No recorder found. Install sox (`rec`) or arecord, or set `audio_recorder.record_cmd`."
end

local function record_cmd(path)
  local record_cmd_opt = opts().record_cmd
  if type(record_cmd_opt) == "function" then
    return record_cmd_opt(path)
  elseif type(record_cmd_opt) == "table" then
    return replace_file_arg(record_cmd_opt, path)
  elseif record_cmd_opt ~= nil then
    return nil, "audio_recorder.record_cmd must be a function or argv table"
  end
  return default_record_cmd(path)
end

local function recording_path()
  local recorder_opts = opts()
  local dir = recorder_opts.recording_dir or vim.fs.joinpath(vim.fn.stdpath "cache", "obsidian.nvim", "recordings")
  local ext = recorder_opts.recording_ext or "wav"
  vim.fn.mkdir(dir, "p")
  return vim.fs.joinpath(dir, string.format("Recording %s.%s", os.date "%Y%m%d%H%M%S", ext))
end

local function is_audio_path(path)
  local clean = path:gsub("#.*$", ""):gsub("%?.*$", "")
  local ext = clean:match "%.([^./]+)$"
  return ext ~= nil and audio_exts[ext:lower()] == true
end

local function insert_link(bufnr, mark_id, link_text)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil, "target buffer is no longer valid"
  end
  if not vim.api.nvim_get_option_value("modifiable", { buf = bufnr }) then
    return nil, "target buffer is not modifiable"
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark_id, {})
  if vim.tbl_isempty(pos) then
    return nil, "recording insertion mark was lost"
  end

  local row, col = pos[1], pos[2]
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { link_text })
  vim.api.nvim_buf_del_extmark(bufnr, ns, mark_id)
  return { row = row + 1, col = col }
end

local function run_callback(ctx)
  local callback = opts().callback
  if type(callback) ~= "function" then
    return false
  end
  return util.fire_callback("audio_recorder", callback, ctx)
end

local function finish_recording(recording)
  vim.schedule(function()
    local stat = vim.uv.fs_stat(recording.temp_path)
    if not stat or stat.size == 0 then
      state.processing = false
      log.err "Recording produced no audio"
      return
    end

    local audio_path = attachment.add(recording.temp_path, { insert = false, bufnr = recording.bufnr })
    if not audio_path then
      state.processing = false
      log.err("Failed to attach recording from %s", recording.temp_path)
      return
    end

    local link_text = attachment.format_link(audio_path)
    local insert_pos, insert_err = insert_link(recording.bufnr, recording.mark_id, link_text)
    if not insert_pos then
      log.warn(insert_err)
    end

    if audio_path ~= recording.temp_path and opts().delete_temp_file ~= false then
      vim.fn.delete(recording.temp_path)
    end

    state.processing = false

    log.info("Audio recording attached as %s (recorded at %s)", audio_path, recording.temp_path)

    if opts().run_callback_on_stop then
      run_callback {
        path = audio_path,
        temp_path = recording.temp_path,
        link = link_text,
        bufnr = recording.bufnr,
        position = insert_pos,
        manual = false,
      }
    end
  end)
end

M.start = function()
  if state.recording then
    log.info "Already recording"
    return
  end
  if state.processing then
    log.info "Still processing previous recording"
    return
  end
  if not vim.b.obsidian_buffer then
    log.warn "Not in an obsidian buffer"
    return
  end

  local temp_path = recording_path()
  local cmd, err = record_cmd(temp_path)
  if not cmd then
    log.warn(err)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, cursor[1] - 1, cursor[2], {
    right_gravity = false,
  })

  state.recording = true
  state.processing = false
  state.temp_path = temp_path
  state.bufnr = bufnr
  state.mark_id = mark_id
  state.started_at = vim.uv.now()

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    if state.recording then
      vim.schedule(function()
        if state.bufnr and state.mark_id and vim.api.nvim_buf_is_valid(state.bufnr) then
          vim.api.nvim_buf_del_extmark(state.bufnr, ns, state.mark_id)
        end
        state.recording = false
        state.job = nil
        state.temp_path = nil
        state.bufnr = nil
        state.mark_id = nil
        state.processing = false
        log.err("Recorder exited early: %s", vim.trim(obj.stderr or obj.stdout or ""))
      end)
    end
  end)
  if not ok then
    vim.api.nvim_buf_del_extmark(bufnr, ns, mark_id)
    state.recording = false
    state.temp_path = nil
    state.bufnr = nil
    state.mark_id = nil
    state.started_at = nil
    log.err("Failed to start recorder: %s", job_or_err)
    return
  end
  state.job = job_or_err

  log.info("Recording audio to %s", temp_path)
end

M.stop = function()
  if not state.recording then
    log.info "Not recording"
    return
  end

  local recording = {
    job = state.job,
    temp_path = state.temp_path,
    bufnr = state.bufnr,
    mark_id = state.mark_id,
  }

  state.recording = false
  state.processing = true
  state.job = nil
  state.temp_path = nil
  state.bufnr = nil
  state.mark_id = nil
  state.started_at = nil

  log.info "Stopping audio recorder"
  if recording.job then
    recording.job:kill(opts().stop_signal or 2)
    recording.job:wait(opts().stop_timeout_ms or 3000)
  end

  finish_recording(recording)
end

M.toggle = function()
  if state.recording then
    M.stop()
  else
    M.start()
  end
end

M.state = function()
  return {
    recording = state.recording,
    processing = state.processing,
    path = state.temp_path,
    bufnr = state.bufnr,
    started_at = state.started_at,
  }
end

M.is_recording = function()
  return state.recording
end

M.attachment_under_cursor = function()
  local api = require "obsidian.api"
  local Path = require "obsidian.path"
  local cursor_link, link_type = api.cursor_link()
  if not cursor_link then
    return nil
  end

  local location = util.parse_link(cursor_link, { strip = true, link_type = link_type })
  if not location or not is_audio_path(location) then
    return nil
  end

  local path
  if vim.startswith(location, "file:/") then
    path = vim.uri_to_fname(location)
  else
    local bufnr = vim.api.nvim_get_current_buf()
    local decoded = vim.uri_decode(location)
    local candidates = {}

    if Path.new(decoded):is_absolute() then
      candidates[#candidates + 1] = decoded
    else
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname ~= "" then
        candidates[#candidates + 1] = vim.fs.joinpath(vim.fs.dirname(bufname), decoded)
      end
      candidates[#candidates + 1] = vim.fs.joinpath(tostring(Obsidian.dir), decoded)
      candidates[#candidates + 1] = attachment.resolve_attachment_path(decoded, bufnr)
    end

    for _, candidate in ipairs(candidates) do
      if vim.uv.fs_stat(candidate) then
        path = candidate
        break
      end
    end
    path = path or candidates[#candidates]
  end
  if not path or not is_audio_path(path) then
    return nil
  end

  return path, cursor_link
end

M.process_attachment = function()
  local path, cursor_link = M.attachment_under_cursor()
  if not path then
    log.warn "No audio attachment link under cursor"
    return
  end

  if type(opts().callback) ~= "function" then
    log.warn "No audio_recorder.callback configured"
    return
  end

  run_callback {
    path = path,
    link = cursor_link,
    bufnr = vim.api.nvim_get_current_buf(),
    manual = true,
  }
end

return M
