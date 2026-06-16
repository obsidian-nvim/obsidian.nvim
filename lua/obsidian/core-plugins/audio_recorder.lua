local M = {}

local attachment = require "obsidian.attachment"
local log = require "obsidian.log"
local Path = require "obsidian.path"
local util = require "obsidian.util"

local ns = vim.api.nvim_create_namespace "obsidian.audio_recorder"
local STOP_SIGNAL = 2
local STOP_TIMEOUT_MS = 3000

local state = {
  recording = false,
  processing = false,
  job = nil,
  temp_path = nil,
  bufnr = nil,
  mark_id = nil,
  temp_dir = nil,
}

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
  return nil, "Audio recorder requires one CLI: `rec` (SoX), `sox`, or `arecord`."
end

local function recording_path()
  local temp_dir = tostring(Path.temp { suffix = "-obsidian-recording" })
  vim.fn.mkdir(temp_dir, "p")

  -- Use Obsidian's recording basename style. The extension stays .wav because the
  -- built-in CLI backends write WAV/PCM, not m4a.
  local name = string.format("Recording %s.wav", os.date "%Y%m%d%H%M%S")
  return vim.fs.joinpath(temp_dir, name), temp_dir
end

local function cleanup(recording)
  if recording.temp_path then
    vim.fn.delete(recording.temp_path)
  end
  if recording.temp_dir then
    vim.fn.delete(recording.temp_dir, "d")
  end
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

local function finish_recording(recording, callback)
  vim.schedule(function()
    local stat = vim.uv.fs_stat(recording.temp_path)
    if not stat or stat.size == 0 then
      cleanup(recording)
      state.processing = false
      log.err "Recording produced no audio"
      return
    end

    local audio_path = attachment.add(recording.temp_path, { insert = false, bufnr = recording.bufnr })
    if not audio_path then
      cleanup(recording)
      state.processing = false
      log.err("Failed to attach recording from %s", recording.temp_path)
      return
    end

    local link_text = attachment.format_link(audio_path)
    local insert_pos, insert_err = insert_link(recording.bufnr, recording.mark_id, link_text)
    if not insert_pos and insert_err then
      log.warn(insert_err)
    end

    cleanup(recording)

    state.processing = false

    log.info("Audio recording attached as %s (recorded at %s)", audio_path, recording.temp_path)

    if type(callback) == "function" then
      util.fire_callback("audio_recorder", callback, {
        path = audio_path,
        temp_path = recording.temp_path,
        link = link_text,
        bufnr = recording.bufnr,
        position = insert_pos,
      })
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

  local temp_path, temp_dir = recording_path()
  local cmd, err = default_record_cmd(temp_path)
  if not cmd then
    cleanup { temp_path = temp_path, temp_dir = temp_dir }
    if err then
      log.warn(err)
    end
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
  state.temp_dir = temp_dir

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    if state.recording then
      vim.schedule(function()
        if state.bufnr and state.mark_id and vim.api.nvim_buf_is_valid(state.bufnr) then
          vim.api.nvim_buf_del_extmark(state.bufnr, ns, state.mark_id)
        end
        cleanup { temp_path = state.temp_path, temp_dir = state.temp_dir }
        state.recording = false
        state.job = nil
        state.temp_path = nil
        state.bufnr = nil
        state.mark_id = nil
        state.temp_dir = nil
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
    state.temp_dir = nil
    cleanup { temp_path = temp_path, temp_dir = temp_dir }
    log.err("Failed to start recorder: %s", job_or_err)
    return
  end
  state.job = job_or_err

  log.info("Recording audio to %s", temp_path)
end

---@param callback fun(ctx: obsidian.AudioRecorderCallbackContext)|?
M.stop = function(callback)
  if not state.recording then
    log.info "Not recording"
    return
  end

  local recording = {
    job = state.job,
    temp_path = state.temp_path,
    bufnr = state.bufnr,
    mark_id = state.mark_id,
    temp_dir = state.temp_dir,
  }

  state.recording = false
  state.processing = true
  state.job = nil
  state.temp_path = nil
  state.bufnr = nil
  state.mark_id = nil
  state.temp_dir = nil

  log.info "Stopping audio recorder"
  if recording.job then
    recording.job:kill(STOP_SIGNAL)
    recording.job:wait(STOP_TIMEOUT_MS)
  end

  finish_recording(recording, callback)
end

M.is_recording = function()
  return state.recording
end

return M
