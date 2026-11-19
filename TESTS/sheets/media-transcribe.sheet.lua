-- Feature media.transcribe (TESTS/sheets/features.lua): `:Media transcribe` through the real pipeline (ffmpeg makes the
-- WAV, the dispatcher caches, media.nvim writes the sidecar) with a stand-in for whisper.cpp's run, and the two error
-- paths of the real whisper.cpp engine (task media.nvim/live-plan-media-live-testing-plan-sortieren-erledigtes-abhak,
-- the live plan's section 9.4 steps 4, 5, 6/7 and 8/9).
-- The stand-in replaces only `transcribe`/`available`/`ready` of the registered whisper_cpp engine and answers at once:
-- a real run needs whisper.cpp and a model of hundreds of megabytes, which no hosted runner has. That the real engine
-- reads the real `-oj` output is whisper_cpp_spec's (the JSON of a real run, commit c84cb86); which arguments `lang=` and
-- `task=translate` become on its command line is whisper_cpp_spec's as well.
return {
  id = "media.transcribe",
  title = ":Media transcribe: sidecar, cache hit, lang= and task=, no model and no whisper-cli",
  task = "media.nvim/live-plan-media-live-testing-plan-sortieren-erledigtes-abhak",
  feature = "media.transcribe",
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
      note = "the test video with a sine tone, whisper.cpp's run replaced by a stand-in",
    },

    -- out=sidecar
    { keys = ":Media transcribe engine=whisper_cpp out=sidecar<CR>" },
    {
      wait = [[_G.exists(_G.video .. ".transcript.md")]],
      timeout = 20000,
      note = "the sidecar <file>.transcript.md is written next to the video",
    },
    {
      expect = [[_G.eq(#_G.heard, 1) and _G.heard[1].wav:match("%.wav$") ~= nil]],
      note = "one run of the engine, on the WAV ffmpeg made",
    },
    {
      expect = [[_G.sidecar():find("Hello from the stand-in", 1, true) ~= nil and _G.sidecar():find("whisper_cpp", 1, true) ~= nil]],
      note = "it holds the text and names the engine",
    },
    {
      expect = [[_G.sidecar():find("clip.mp4", 1, true) ~= nil and _G.sidecar():find("%d%d%d%d%-%d%d%-%d%d") ~= nil]],
      note = "and the file it is for and a date",
    },

    -- the cache
    {
      -- the dispatcher writes the cached transcript after it has delivered the result (fire-and-forget,
      -- core/dispatcher.lua); a second call before that write is a cache miss, which under load made this sheet flaky
      wait = [[vim.iter(vim.fn.glob(require("media.core.cache").dir() .. "/*.json", true, true)):any(function(f) return vim.fn.getfsize(f) > 0 end)]],
      timeout = 10000,
      note = "the transcript is in the cache",
    },
    { lua = [[_G.forget()]] },
    { keys = ":Media transcribe engine=whisper_cpp<CR>" },
    {
      wait = [[_G.buftext():find("Hello from the stand-in", 1, true) ~= nil]],
      timeout = 10000,
      note = "the same file again: the transcript opens in a buffer",
    },
    {
      expect = [[_G.eq(#_G.heard, 1)]],
      note = "from the cache, without a second run of the engine",
    },

    -- lang= and task=
    { lua = [[_G.back_to_video()]], note = "back in the video's buffer" },
    { keys = ":Media transcribe engine=whisper_cpp lang=de task=translate<CR>" },
    { wait = [[#_G.heard == 2]], timeout = 20000, note = "another language is another run" },
    {
      expect = [[_G.eq({ _G.heard[2].lang, _G.heard[2].task }, { "de", "translate" })]],
      note = "lang= and task= reach the engine",
    },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level so far" },

    -- the cache thrown away, or the runs below would be answered from it
    { lua = [[_G.back_to_video(); _G.forget()]] },
    { keys = ":Media cache clear<CR>" },
    {
      expect = [[_G.noted("cached still(s) removed") and not _G.noted("0 cached")]],
      note = ":Media cache clear removes the WAVs and transcripts",
    },

    -- the real engine, no model
    {
      lua = [[_G.whisper_stand_in(false); _G.forget(); require("media").setup({ bin = { ["whisper-cli"] = vim.v.progpath }, transcribe = { whisper_cpp = { model = _G.dir .. "/no-such-model.bin" } } })]],
      note = "the real engine; whisper-cli is there (any program will do), the model is not",
    },
    { lua = [[_G.back_to_video()]], note = "back in the video's buffer" },
    { keys = ":Media transcribe engine=whisper_cpp<CR>" },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("whisper.cpp model not found", 1, true) ~= nil]],
      timeout = 10000,
      note = "one line says the model is not found",
    },
    { expect = [[_G.noted("no-such-model.bin")]], note = "and names the path" },

    -- the real engine, no whisper-cli
    {
      lua = [[_G.forget(); require("media").setup({ bin = { ["whisper-cli"] = _G.dir .. "/no-such-whisper-cli" }, transcribe = { whisper_cpp = { model = _G.video } } })]],
      note = "whisper-cli points to nothing now",
    },
    { lua = [[_G.back_to_video()]], note = "back in the video's buffer" },
    { keys = ":Media transcribe engine=whisper_cpp<CR>" },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("could not start whisper-cli", 1, true) ~= nil]],
      timeout = 10000,
      note = "one line says whisper-cli is missing",
    },
    { expect = [[vim.api.nvim_get_mode().mode == "n"]], note = "no hang, the editor goes on" },

    -- the openai-whisper engine (media.engines.whisper_cli, shared with faster-whisper): a `whisper` that fails
    {
      lua = [[_G.forget(); _G.warnings = {}; require("media").setup({ bin = { whisper = vim.v.progpath }, transcribe = { openai_whisper = { model = _G.video } } })]],
      note = "whisper is a program that refuses the arguments (Neovim itself), the model a file that exists",
    },
    { lua = [[_G.back_to_video()]], note = "back in the video's buffer" },
    { keys = ":Media transcribe engine=openai_whisper<CR>" },
    {
      wait = [[#_G.warnings > 0]],
      timeout = 20000,
      note = "the run ends in one line",
    },
    {
      expect = [[table.concat(_G.warnings, "\n"):find("whisper exited with", 1, true) ~= nil and vim.api.nvim_get_mode().mode == "n"]],
      note = "it says whisper failed and how, no hang",
    },
  },
  judge = { "the sidecar reads well: title, date, engine line, text" },
  manual = {
    "With a real whisper.cpp and a real speech recording: the text is roughly what was said, a second run answers at once from the cache, lang= helps and task=translate yields English",
  },
}
