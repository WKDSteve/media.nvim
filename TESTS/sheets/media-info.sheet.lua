-- Live check: `:Media engines`, `:Media health` and `:Media probe` (task media.nvim/testblatt-bindings-checkliste;
-- the :Media section of BINDINGS-RUNTIME-CHECKLIST.md). Needs ffmpeg and ffprobe for the test video.
return {
  id = "media.info",
  title = ":Media engines, health and probe",
  task = "media.nvim/testblatt-bindings-checkliste",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    {
      lua = [[vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1]],
      reason = "ffmpeg and ffprobe are not installed",
    },
  },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":Media engines<CR>" },
    {
      expect = [[_G.noted("whisper_cpp") and _G.noted("faster_whisper") and _G.noted("openai_whisper")]],
      note = "engines lists the registered engines with their availability",
    },
    { lua = [[_G.forget()]] },
    { keys = ":Media probe<CR>" },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "probe of the buffer's file opens its record",
    },
    {
      expect = [[_G.floattext():find("h264", 1, true) and _G.floattext():find("440", 1, true) == nil]],
      note = "video codec in the record",
    },
    { keys = "q" },
    { keys = ":Media<CR>" },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "bare :Media describes the file as well",
    },
    { keys = "q" },
    { keys = ":Media health<CR>" },
    {
      wait = [[vim.bo.filetype == "checkhealth"]],
      timeout = 10000,
      note = "health opens :checkhealth media",
    },
    {
      expect = [[table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("media", 1, true) ~= nil]],
    },
  },
  judge = {
    "the probe record reads well (aligned rows, units)",
    "the health report names the tools it found",
  },
}
