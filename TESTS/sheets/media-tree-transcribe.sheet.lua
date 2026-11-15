-- Feature media.tree-actions (TESTS/sheets/features.lua), transcribe: in the real own tree of filetree.nvim a
-- recording with a transcript next to it carries the badge `transcript`, one without has none (media.tree-badge).
-- "Transcribe this recording into a file next to it" from the context menu writes `<file>.transcript.md`, and the
-- badge follows without a scan; the configured key does the same on an audio file. Without an engine nothing is
-- started and one line says what is missing.
-- The engine is a stand-in in Lua that answers at once (TESTS/sheets/_helpers.lua `engine_stand_in`): a real
-- engine is ffmpeg, then whisper with a model of hundreds of megabytes, and a recording stand-in for a program
-- writes no file the next program could read. The transcript itself is written by media.nvim. Which arguments
-- each engine gets is the suite's (whisper_cpp_spec, faster_whisper_spec, openai_whisper_spec).
return {
  id = "media.tree-transcribe",
  feature = "media.tree-actions",
  title = "media.nvim: transcribe from the menu and the key of a media node writes the sidecar, the badge follows",
  task = "images.nvim/own-tree-feature-sheets-images-media-pickers",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.tree_boot(); _G.engine_stand_in()]],
      note = "the project recordings, media.nvim with an engine that answers at once, the own tree on the left",
    },
    {
      lua = [[_G.on("talks/standup.mp4")]],
      note = "open talks in the tree, the cursor on the video",
    },

    -- the badge
    {
      wait = [[_G.row_has("talks/retro.mp4", "transcript")]],
      timeout = 10000,
      note = "the video with a transcript next to it has the badge, once the scan in the background ended",
    },
    {
      expect = [[_G.eq(_G.row("talks/standup.mp4"), "      standup.mp4")]],
      note = "the video without one has none",
    },
    {
      expect = [[_G.eq(_G.row("talks/retro.mp4.transcript.md"), "      retro.mp4.transcript.md")]],
      note = "nor has the transcript itself",
    },

    -- transcribe from the menu
    {
      lua = [[_G.right_click("talks/standup.mp4")]],
      note = "a right click on the video without a transcript",
    },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Transcribe this recording into a file next to it")]],
      note = "it offers to transcribe the recording",
    },
    { keys = "<CR>", note = "pick the entry" },
    {
      wait = [[_G.exists(_G.rec .. "/talks/standup.mp4.transcript.md")]],
      timeout = 10000,
      note = "the transcript is written next to the video",
    },
    {
      expect = [[_G.eq(_G.transcribed, { _G.rec .. "/talks/standup.mp4" })]],
      note = "with one run of the engine, on the video of the node",
    },
    {
      expect = [[table.concat(vim.fn.readfile(_G.rec .. "/talks/standup.mp4.transcript.md"), "\n"):find("Hello from the stand-in", 1, true) ~= nil]],
      note = "it holds what the engine heard",
    },
    {
      wait = [[_G.row_has("talks/standup.mp4", "transcript")]],
      timeout = 10000,
      note = "and the badge follows",
    },
    { lua = [[_G.close_floats()]] },

    -- transcribe from the key, on an audio file
    { lua = [[_G.on("audio/jingle.mp3")]], note = "the cursor on the audio file" },
    {
      expect = [[_G.eq(_G.row("audio/jingle.mp3"), "      jingle.mp3")]],
      note = "no transcript yet",
    },
    { keys = "gmt", note = "the key the config gave the action" },
    {
      wait = [[_G.exists(_G.rec .. "/audio/jingle.mp3.transcript.md")]],
      timeout = 10000,
      note = "the transcript is written next to the audio file",
    },
    {
      wait = [[_G.row_has("audio/jingle.mp3", "transcript")]],
      timeout = 10000,
      note = "and the badge follows",
    },
    { lua = [[_G.close_floats()]] },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level so far" },

    -- without an engine
    {
      lua = [[_G.engine_stand_in(false); _G.on("talks/retro.mp4")]],
      note = "no engine is installed now",
    },
    { keys = "gmt", note = "the key on a recording" },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("no engine is installed", 1, true) ~= nil]],
      timeout = 5000,
      note = "one line says what is missing",
    },
    { expect = [[_G.eq(_G.transcribed, {})]], note = "and nothing is started" },
  },
  manual = {
    "In the real editor with a real engine (whisper.cpp or faster-whisper) and a real recording: the transcript holds what is said, the progress is shown while it runs, and the badge appears when it ends",
  },
}
