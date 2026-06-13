# Audio recorder

The audio recorder mirrors Obsidian's core audio recorder: start recording from a note, stop it, and obsidian.nvim attaches the audio file to the vault and inserts the attachment link at the cursor position that started the recording.

## Code actions

Use your normal LSP code action mapping in a note:

- `Record audio as attachment` starts recording.
- `Stop recording` appears only while a recording is active.
- `Process audio attachment` appears on audio attachment links and runs the optional callback.

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

Recordings are first written to `audio_recorder.recording_dir` and then copied with `obsidian.attachment.add()` into your configured attachments folder. The temporary file is deleted by default after it is attached.

obsidian.nvim logs both paths when the recording is attached.

## Callback for transcription or summaries

The recorder does not include transcription or summarization. Configure a callback for that work:

```lua
require("obsidian").setup {
  audio_recorder = {
    run_callback_on_stop = true,
    callback = function(ctx)
      -- ctx.path: attached audio file in the vault
      -- ctx.link: inserted or selected attachment link
      -- ctx.bufnr: note buffer
      -- ctx.manual: false after recording, true from the manual code action
    end,
  },
}
```

Set `run_callback_on_stop = false` and use `Process audio attachment` on an audio link if you prefer to run the callback manually.

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

require("obsidian").setup {
  audio_recorder = {
    run_callback_on_stop = true,
    callback = transcribe_with_whisper,
  },
}
```
