# Audio recorder

The audio recorder mirrors Obsidian's core audio recorder: start recording from a note, stop it, then obsidian.nvim attaches the audio file to the vault and inserts the attachment link at the cursor position that started the recording.

## Code actions

Use your normal LSP code action mapping in a note:

- `Record audio as attachment` starts recording.
- `Stop recording` appears only while a recording is active.

The insertion point is tracked with an extmark, so edits above the cursor while recording should not move the final link to the wrong place.

## Recording backend

By default obsidian.nvim looks for one of:

- `rec` from sox
- `sox`
- `arecord`

`:checkhealth obsidian` reports the available backend. Starting a recording also warns if no backend is available.

You can override the command:

```lua
require("obsidian").setup {
  audio_recorder = {
    record_cmd = { "rec", "-q", "{file}" },
    -- or:
    -- record_cmd = function(path)
    --   return { "arecord", "-q", "-f", "cd", "-t", "wav", path }
    -- end,
  },
}
```

## Storage

Recordings are first written to a temp file and then copied with `obsidian.attachment.add()` into your configured attachments folder. The temporary file is deleted by default after it is attached.

obsidian.nvim logs both paths when the recording is attached.

## Callback for transcription or summaries

By default, stopping a recording only inserts the attachment link. To run transcription, summary, or other custom logic after the link is inserted, wrap `actions.stop_recording()`:

```lua
local actions = require "obsidian.actions"
local stop_recording = actions.stop_recording

actions.stop_recording = function()
  stop_recording(function(ctx)
    -- ctx.path: attached audio file in the vault
    -- ctx.link: inserted attachment link
    -- ctx.bufnr: note buffer
    -- ctx.position: inserted link position, if insertion succeeded
  end)
end
```

### Minimal Whisper API example

This callback sends the audio file to OpenAI's Whisper API and appends the transcript below the note:

```lua
local function transcribe_with_whisper(ctx)
  local key = vim.env.OPENAI_API_KEY
  if not key or key == "" then
    vim.notify("OPENAI_API_KEY is not set", vim.log.levels.ERROR)
    return
  end

  vim.system({
    "curl",
    "-sS",
    "https://api.openai.com/v1/audio/transcriptions",
    "-H",
    "Authorization: Bearer " .. key,
    "-F",
    "model=whisper-1",
    "-F",
    "file=@" .. ctx.path,
  }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify(obj.stderr or obj.stdout, vim.log.levels.ERROR)
        return
      end

      local ok, decoded = pcall(vim.json.decode, obj.stdout)
      if not ok or not decoded.text then
        vim.notify("Failed to parse Whisper response", vim.log.levels.ERROR)
        return
      end

      vim.api.nvim_buf_set_lines(ctx.bufnr, -1, -1, false, {
        "",
        "## Transcript",
        "",
        decoded.text,
      })
    end)
  end)
end

local actions = require "obsidian.actions"
local stop_recording = actions.stop_recording

actions.stop_recording = function()
  stop_recording(transcribe_with_whisper)
end
```
