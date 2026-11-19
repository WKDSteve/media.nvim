-- Feature media.dashboard (TESTS/sheets/features.lua): `:Media dashboard path=<dir>` lists the media files of a folder
-- with the state of their text (missing, stale, fine), probes their durations, and <CR> on a row without text makes it:
-- for a video that is the transcript sidecar, through the real pipeline (ffmpeg makes the WAV) with the stand-in for
-- whisper.cpp's run of _helpers.lua (a real model is hundreds of megabytes, which no hosted runner has).
return {
  id = "media.dashboard",
  feature = "media.dashboard",
  title = ":Media dashboard lists a folder's media with their text state, <CR> makes the missing transcript",
  engine = "rpc",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    {
      lua = [[vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1]],
      reason = "ffmpeg and ffprobe are not installed",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot(); _G.whisper_stand_in()]],
      note = "the test video in a temp folder, whisper.cpp's run replaced by a stand-in",
    },
    {
      lua = [[vim.cmd("Media dashboard path=" .. vim.fn.fnameescape(_G.dir))]],
      note = ":Media dashboard path=<the folder>",
    },
    {
      wait = [[vim.bo.filetype == "media-dashboard" and _G.buftext():find("clip.mp4", 1, true) ~= nil]],
      timeout = 10000,
      note = "the dashboard opens and lists the video",
    },
    {
      expect = [[_G.line_with("clip.mp4"):find("missing", 1, true) ~= nil]],
      note = "its transcript is missing",
    },
    {
      lua = [[vim.fn.search("clip.mp4")]],
      note = "the cursor on the video's row",
    },
    { keys = "<CR>", note = "<CR> does the obvious thing" },
    {
      wait = [[_G.exists(_G.video .. ".transcript.md")]],
      timeout = 20000,
      note = "the transcript sidecar is written next to the video",
    },
    {
      expect = [[_G.eq(#_G.heard, 1) and _G.sidecar():find("Hello from the stand-in", 1, true) ~= nil]],
      note = "by one run of the engine, with its text",
    },

    { lua = [[_G.back_to_video(); _G.forget()]] },
    {
      lua = [[vim.cmd("Media dashboard path=" .. vim.fn.fnameescape(_G.dir))]],
      note = "the dashboard again",
    },
    {
      wait = [[vim.bo.filetype == "media-dashboard" and _G.buftext():find("clip.mp4", 1, true) ~= nil]],
      timeout = 10000,
    },
    {
      expect = [[_G.line_with("clip.mp4"):find("missing", 1, true) == nil]],
      note = "its transcript is not missing any more",
    },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
  judge = { "the rows read well: marker, name, kind, duration, the state of the text" },
}
