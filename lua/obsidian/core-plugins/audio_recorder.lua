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
  name = nil,
  bufnr = nil,
  mark_id = nil,
}

local function cleanup(recording)
  if recording.temp_path then
    vim.fn.delete(recording.temp_path)
  end
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
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, cursor[1] - 1, cursor[2], {
    right_gravity = false,
  })

  state.recording = true
  state.processing = false
  state.temp_path = temp_path
  state.name = name
  state.bufnr = bufnr
  state.mark_id = mark_id

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    if state.recording then
      vim.schedule(function()
        if state.bufnr and state.mark_id and vim.api.nvim_buf_is_valid(state.bufnr) then
          vim.api.nvim_buf_del_extmark(state.bufnr, ns, state.mark_id)
        end
        cleanup { temp_path = state.temp_path }
        state.recording = false
        state.job = nil
        state.temp_path = nil
        state.name = nil
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
    state.name = nil
    state.bufnr = nil
    state.mark_id = nil
    cleanup { temp_path = temp_path }
    log.err("Failed to start recorder: %s", job_or_err)
    return
  end
  state.job = job_or_err

  log.info("Recording audio to %s", temp_path)
end

---@class obsidian.AudioRecorderCallbackContext
---@field path string Attached audio path in the vault.
---@field link string Inserted attachment link.
---@field bufnr integer Buffer number associated with the action.
---@field position? { row: integer, col: integer } 1-indexed row and 0-indexed column where the link was inserted.

---@param callback fun(ctx: obsidian.AudioRecorderCallbackContext)|?
M.stop = function(callback)
  if not state.recording then
    log.info "Not recording"
    return
  end

  local recording = {
    job = state.job,
    temp_path = state.temp_path,
    name = state.name,
    bufnr = state.bufnr,
    mark_id = state.mark_id,
  }

  state.recording = false
  state.processing = true
  state.job = nil
  state.temp_path = nil
  state.name = nil
  state.bufnr = nil
  state.mark_id = nil

  log.info "Stopping audio recorder"
  if recording.job then
    recording.job:kill(STOP_SIGNAL)
    recording.job:wait(STOP_TIMEOUT_MS)
  end

  vim.schedule(function()
    local stat = vim.uv.fs_stat(recording.temp_path)
    if not stat or stat.size == 0 then
      cleanup(recording)
      state.processing = false
      log.err "Recording produced no audio"
      return
    end

    local audio_path = attachment.add(recording.temp_path, {
      insert = false,
      bufnr = recording.bufnr,
      new_name = recording.name,
    })
    if not audio_path then
      cleanup(recording)
      state.processing = false
      log.err("Failed to attach recording from %s", recording.temp_path)
      return
    end

    local link_text = attachment.format_link(audio_path)
    local insert_pos, insert_err
    if not (recording.bufnr and vim.api.nvim_buf_is_valid(recording.bufnr)) then
      insert_err = "target buffer is no longer valid"
    elseif not vim.api.nvim_get_option_value("modifiable", { buf = recording.bufnr }) then
      insert_err = "target buffer is not modifiable"
    else
      local pos = vim.api.nvim_buf_get_extmark_by_id(recording.bufnr, ns, recording.mark_id, {})
      if vim.tbl_isempty(pos) then
        insert_err = "recording insertion mark was lost"
      else
        local row, col = pos[1], pos[2]
        vim.api.nvim_buf_set_text(recording.bufnr, row, col, row, col, { link_text })
        vim.api.nvim_buf_del_extmark(recording.bufnr, ns, recording.mark_id)
        insert_pos = { row = row + 1, col = col }
      end
    end
    if not insert_pos and insert_err then
      log.warn(insert_err)
    end

    cleanup(recording)

    state.processing = false

    log.info("Audio recording attached as %s (recorded at %s)", audio_path, recording.temp_path)

    if type(callback) == "function" then
      util.fire_callback("audio_recorder", callback, {
        path = audio_path,
        link = link_text,
        bufnr = recording.bufnr,
        position = insert_pos,
      })
    end
  end)
end

M.is_recording = function()
  return state.recording
end

return M
