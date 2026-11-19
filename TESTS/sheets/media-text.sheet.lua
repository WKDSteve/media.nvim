-- Feature media.text (TESTS/sheets/features.lua): `:Media text` picks the tool by the kind of file. For a video it is
-- the transcript, through the real pipeline (ffmpeg makes the WAV) with the stand-in for whisper.cpp's run of
-- _helpers.lua; out=sidecar writes it next to the video. For an image (OCR, images.nvim) and a PDF (pdfport.nvim) the
-- tool lives in another plugin, which is not installed here: one line says which, with the fix. That the OCR and the
-- PDF text themselves work is those plugins' own sheets'.
return {
  id = "media.text",
  feature = "media.text",
  title = ":Media text: a video becomes its transcript, an image or a PDF without its plugin is one readable line",
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
      note = "the test video, whisper.cpp's run replaced by a stand-in",
    },

    -- a video: its transcript
    { keys = ":Media text out=sidecar<CR>" },
    {
      wait = [[_G.exists(_G.video .. ".transcript.md")]],
      timeout = 20000,
      note = "the transcript sidecar is written next to the video",
    },
    {
      expect = [[_G.eq(#_G.heard, 1) and _G.sidecar():find("Hello from the stand-in", 1, true) ~= nil]],
      note = "by one run of the engine, with its text",
    },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },

    -- an image and a PDF, whose tools are other plugins
    {
      lua = [[_G.back_to_video(); _G.forget(); _G.image = _G.dir .. "/shot.png"; vim.fn.writefile({ "" }, _G.image); _G.pdf = _G.dir .. "/doc.pdf"; vim.fn.writefile({ "%PDF-1.4" }, _G.pdf)]],
      note = "an image and a PDF beside the video",
    },
    {
      lua = [[vim.cmd("Media text " .. vim.fn.fnameescape(_G.image))]],
      note = ":Media text <image>",
    },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("images.nvim is not installed", 1, true) ~= nil]],
      timeout = 10000,
      note = "one line says OCR needs images.nvim",
    },
    { lua = [[_G.warnings = {}]] },
    { lua = [[vim.cmd("Media text " .. vim.fn.fnameescape(_G.pdf))]], note = ":Media text <pdf>" },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("pdfport.nvim is not installed", 1, true) ~= nil]],
      timeout = 10000,
      note = "one line says the PDF text needs pdfport.nvim",
    },
    { expect = [[vim.api.nvim_get_mode().mode == "n"]], note = "no hang, the editor goes on" },
  },
  manual = {
    "With images.nvim and tesseract: :Media text on a screenshot gives its text; with pdfport.nvim the text of a PDF",
  },
}
