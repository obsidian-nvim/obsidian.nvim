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

The temporary recording file uses a `.wav` suffix because the built-in CLI backends write WAV/PCM audio. Obsidian's app commonly records `.m4a`, but these CLI tools do not reliably encode m4a without extra codec support.

## Storage

Recordings are first written to a temp file and then copied with `obsidian.attachment.add()` into your configured attachments folder using an Obsidian-style `Recording YYYYMMDDHHMMSS.wav` name. The temporary file is deleted by default after it is attached.

obsidian.nvim logs both paths when the recording is attached.

## Callback for transcription or summaries

Stopping a recording adds the audio through the normal attachment pipeline. Use `callbacks.add_attachment` or the `ObsidianAttachmentAdded` user autocmd to run transcription, summary, or other custom logic after the link is inserted.

### Minimal Whisper API example

This callback sends recorded audio files to OpenAI's Whisper API and appends the transcript below the note:

```lua
local function transcribe_with_whisper(path, ctx)
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
    "file=@" .. tostring(path),
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

      vim.api.nvim_buf_set_lines(ctx.buffer, -1, -1, false, {
        "",
        "## Transcript",
        "",
        decoded.text,
      })
    end)
  end)
end

require("obsidian").setup {
  callbacks = {
    add_attachment = function(path, ctx)
      if ctx.scope == "audio_recorder" then
        transcribe_with_whisper(path, ctx)
      end
    end,
  },
}
```
