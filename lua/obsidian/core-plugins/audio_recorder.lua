local M = {}

local attachment = require "obsidian.attachment"
local log = require "obsidian.log"
local Path = require "obsidian.path"

local ns = vim.api.nvim_create_namespace "obsidian.audio_recorder"
local STOP_SIGNAL = 2
local STOP_TIMEOUT_MS = 3000

---@class obsidian.AudioRecorderJob
---@field kill fun(self: obsidian.AudioRecorderJob, signal?: integer)
---@field wait fun(self: obsidian.AudioRecorderJob, timeout?: integer): any

---@class obsidian.AudioRecorderRecording
---@field temp_path string Temporary recording path.
---@field name string Destination attachment basename.
---@field bufnr integer Target buffer for link insertion.
---@field mark_id integer Extmark tracking the insertion point.
---@field job? obsidian.AudioRecorderJob Recording process handle.

---@class obsidian.AudioRecorderState
---@field recording obsidian.AudioRecorderRecording|nil Active recording, if any.
---@field processing boolean Whether a stopped recording is being attached.

---@type obsidian.AudioRecorderState
local state = {
  recording = nil,
  processing = false,
}

---@param recording { temp_path?: string }
local function cleanup(recording)
  if recording.temp_path then
    vim.fn.delete(recording.temp_path)
  end
end

---@param recording obsidian.AudioRecorderRecording
local function delete_mark(recording)
  if recording.bufnr and recording.mark_id and vim.api.nvim_buf_is_valid(recording.bufnr) then
    vim.api.nvim_buf_del_extmark(recording.bufnr, ns, recording.mark_id)
  end
end

---@param recording obsidian.AudioRecorderRecording
local function clear_recording(recording)
  if state.recording == recording then
    state.recording = nil
  end
end

---@param bufnr integer
---@param row integer 0-indexed row.
---@param col integer 0-indexed column.
---@return integer col 0-indexed column after the cursor character.
local function cursor_insert_col_after(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  if col >= #line then
    return #line
  end

  return vim.str_byteindex(line, vim.str_utfindex(line, col) + 1)
end

---@param recording obsidian.AudioRecorderRecording
---@return obsidian.AttachmentPosition? position
---@return string? error
local function take_insert_position(recording)
  if not (recording.bufnr and vim.api.nvim_buf_is_valid(recording.bufnr)) then
    return nil, "target buffer is no longer valid"
  elseif not vim.api.nvim_get_option_value("modifiable", { buf = recording.bufnr }) then
    delete_mark(recording)
    return nil, "target buffer is not modifiable"
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(recording.bufnr, ns, recording.mark_id, {})
  delete_mark(recording)
  if vim.tbl_isempty(pos) then
    return nil, "recording insertion mark was lost"
  end

  return { row = pos[1] + 1, col = pos[2] }
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

  -- Use Obsidian's recording basename style for the attached file. The extension
  -- stays .wav because the built-in CLI backends write WAV/PCM, not m4a.
  local temp_path = tostring(Path.temp { suffix = ".wav" })
  local name = string.format("Recording %s.wav", os.date "%Y%m%d%H%M%S")

  ---@type string[]?
  local cmd
  if vim.fn.executable "rec" == 1 then
    cmd = { "rec", "-q", "-c", "1", "-r", "16000", temp_path }
  elseif vim.fn.executable "sox" == 1 then
    cmd = { "sox", "-q", "-d", "-c", "1", "-r", "16000", temp_path }
  elseif vim.fn.executable "arecord" == 1 then
    cmd = { "arecord", "-q", "-f", "cd", "-t", "wav", temp_path }
  else
    cleanup { temp_path = temp_path }
    log.warn "Audio recorder requires one CLI: `rec` (SoX), `sox`, or `arecord`."
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local recording = {
    temp_path = temp_path,
    name = name,
    bufnr = bufnr,
    mark_id = vim.api.nvim_buf_set_extmark(
      bufnr,
      ns,
      cursor[1] - 1,
      cursor_insert_col_after(bufnr, cursor[1] - 1, cursor[2]),
      {
        right_gravity = false,
      }
    ),
  }
  state.recording = recording
  state.processing = false

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    if state.recording == recording then
      vim.schedule(function()
        if state.recording ~= recording then
          return
        end
        delete_mark(recording)
        cleanup(recording)
        clear_recording(recording)
        state.processing = false
        log.err("Recorder exited early: %s", vim.trim(obj.stderr or obj.stdout or ""))
      end)
    end
  end)
  if not ok then
    delete_mark(recording)
    cleanup(recording)
    clear_recording(recording)
    log.err("Failed to start recorder: %s", job_or_err)
    return
  end
  ---@cast job_or_err obsidian.AudioRecorderJob
  recording.job = job_or_err

  log.info("Recording audio to %s", temp_path)
end

M.stop = function()
  local recording = state.recording
  if not recording then
    log.info "Not recording"
    return
  end

  clear_recording(recording)
  state.processing = true

  log.info "Stopping audio recorder"
  if recording.job then
    recording.job:kill(STOP_SIGNAL)
    recording.job:wait(STOP_TIMEOUT_MS)
  end

  vim.schedule(function()
    local stat = vim.uv.fs_stat(recording.temp_path)
    if not stat or stat.size == 0 then
      delete_mark(recording)
      cleanup(recording)
      state.processing = false
      log.err "Recording produced no audio"
      return
    end

    local position, insert_err = take_insert_position(recording)
    if insert_err then
      log.warn(insert_err)
    end

    ---@type integer?
    local bufnr = recording.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      bufnr = nil
    end

    local audio_path = attachment.add(recording.temp_path, {
      insert = position ~= nil,
      bufnr = bufnr,
      new_name = recording.name,
      position = position,
      scope = "audio_recorder",
    })
    if not audio_path then
      cleanup(recording)
      state.processing = false
      log.err("Failed to attach recording from %s", recording.temp_path)
      return
    end

    cleanup(recording)
    state.processing = false

    log.info("Audio recording attached as %s (recorded at %s)", audio_path, recording.temp_path)
  end)
end

M.is_recording = function()
  return state.recording ~= nil
end

M.toggle = function()
  if M.is_recording() then
    M.stop()
  else
    M.start()
  end
end

return M
