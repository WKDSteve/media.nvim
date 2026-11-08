-- Live check: the stills (`:Media frame`, `:Media sheet`) and the four global keys on a real video
-- (task media.nvim/testblatt-bindings-checkliste). The picture viewer and the external player are replaced
-- by recorders, so the check is that the right file is handed over.
return {
  id = "media.render",
  title = ":Media frame and sheet, and the keys <leader>Mp Mf Ms Mo",
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
    { keys = ":Media frame at=1 width=200<CR>" },
    {
      wait = [[_G.shown ~= nil]],
      timeout = 15000,
      note = "frame renders a still and hands it to the viewer",
    },
    {
      expect = [[_G.shown:match("%.png$") ~= nil and vim.fn.filereadable(_G.shown) == 1]],
      note = "a PNG that exists",
    },
    { expect = [[_G.noted("rendering frame")]], note = "and it said it was rendering" },
    { lua = [[_G.forget()]] },
    { keys = ":Media sheet rows=2 cols=2 width=400<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 20000, note = "sheet renders a contact sheet" },
    { expect = [[_G.shown:match("%.png$") ~= nil and vim.fn.filereadable(_G.shown) == 1]] },
    { lua = [[_G.forget()]] },
    { keys = [[\Mf]] },
    {
      wait = [[_G.shown ~= nil]],
      timeout = 15000,
      note = "<leader>Mf is :Media frame on the buffer's file",
    },
    { lua = [[_G.forget()]] },
    { keys = [[\Ms]] },
    { wait = [[_G.shown ~= nil]], timeout = 20000, note = "<leader>Ms is :Media sheet" },
    { lua = [[_G.forget()]] },
    { keys = [[\Mo]] },
    {
      expect = [[_G.played == _G.video or vim.fs.normalize(_G.played or "") == vim.fs.normalize(_G.video)]],
      note = "<leader>Mo hands the file to the player",
    },
    { keys = [[\Mp]] },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "<leader>Mp describes the file",
    },
  },
  judge = { "the poster frame and the contact sheet look right (not black, in the right order)" },
  manual = { "<leader>Mo really starts the configured external player" },
}
