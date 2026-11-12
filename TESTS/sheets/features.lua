-- TESTS/sheets/features.lua -- the functionalities of media.nvim as its user meets them; `testing sheets report` says
-- which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names an
-- id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/what-you-get.md and docs/commands.md (there is no manual checklist for media.nvim).
-- The two sheets require ffmpeg and ffprobe; the workflow installs ffmpeg on every hosted leg (`packages` in
-- .testing.lua), so they run there and name their feature (a requires skip of a feature sheet is red under CI).
return {
  {
    id = "media.describe",
    title = "Describe the media file under the cursor or by name: duration, codecs, size, streams",
    surface = { "binding:<leader>Mp", "command:Media", "command:Media probe" },
    docs = "docs/commands.md",
  },
  {
    id = "media.stills",
    title = "A poster frame or a contact sheet of a video, shown as a picture",
    surface = {
      "binding:<leader>Mf",
      "binding:<leader>Ms",
      "command:Media frame",
      "command:Media sheet",
    },
    docs = "docs/commands.md",
  },
  {
    id = "media.audio-pictures",
    title = "A waveform or a spectrogram of the audio track",
    surface = { "command:Media waveform", "command:Media spectrogram" },
    docs = "docs/commands.md",
  },
  {
    id = "media.play",
    title = "Play the file in an external player, or in a real mpv window from a given time",
    surface = { "binding:<leader>Mo", "command:Media play", "command:Media window" },
    docs = "docs/commands.md",
  },
  {
    id = "media.dashboard",
    title = "One list across image, PDF, audio and video files: text missing, stale or fine, with batch actions",
    surface = { "command:Media dashboard" },
    docs = "docs/commands.md",
  },
  {
    id = "media.text",
    title = "Anything to text: OCR of an image, the text of a PDF, the transcript of audio or video",
    surface = { "command:Media text" },
    docs = "docs/commands.md",
  },
  {
    id = "media.transcribe",
    title = "Speech to text into a buffer, a .transcript.md sidecar or subtitles, with the engines listed",
    surface = { "command:Media transcribe", "command:Media engines" },
    docs = "docs/commands.md",
  },
  {
    id = "media.health",
    title = ":Media health and :checkhealth media say which external tools are there",
    surface = { "command:Media health" },
    docs = "docs/health.md",
  },
  {
    id = "media.cache",
    title = "Rendered stills, WAVs and transcripts are cached, and :Media cache clear throws them away",
    surface = { "command:Media cache clear" },
    docs = "docs/commands.md",
  },
}
