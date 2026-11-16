-- Feature media.audio-pictures (TESTS/sheets/features.lua): `:Media waveform` and `:Media spectrogram` on a real video
-- with a sine tone render a PNG of the asked size; a video without a sound track and a file that is not there end in
-- one readable line, not in a crash or an empty picture (task media.nvim/live-plan-media-live-testing-plan-sortieren-
-- erledigtes-abhak, the live plan's sections 3 and 4). The picture viewer is a recorder (TESTS/sheets/_helpers.lua), so
-- the check is the file handed over; whether the picture looks right is the judge's.
return {
  id = "media.audio-pictures",
  title = ":Media waveform and spectrogram, their size, and the paths without sound or without a file",
  task = "media.nvim/live-plan-media-live-testing-plan-sortieren-erledigtes-abhak",
  feature = "media.audio-pictures",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    {
      lua = [[vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1]],
      reason = "ffmpeg and ffprobe are not installed",
    },
  },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },

    -- the two pictures of the sound track
    { keys = ":Media waveform<CR>" },
    {
      wait = [[_G.shown ~= nil]],
      timeout = 20000,
      note = "waveform renders a picture and hands it to the viewer",
    },
    {
      expect = [[_G.shown:match("%.png$") ~= nil and vim.fn.filereadable(_G.shown) == 1]],
      note = "a PNG that exists",
    },
    {
      expect = [[_G.noted("rendering waveform") and #_G.warnings == 0]],
      note = "it said so, nothing went wrong",
    },
    { lua = [[_G.forget()]] },
    { keys = ":Media spectrogram<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 20000, note = "spectrogram renders a picture as well" },
    {
      expect = [[_G.shown:match("%.png$") ~= nil and vim.fn.filereadable(_G.shown) == 1 and #_G.warnings == 0]],
    },

    -- width= and height=
    { lua = [[_G.forget()]] },
    { keys = ":Media waveform width=600 height=150<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 20000, note = "width= and height= reach the render" },
    {
      expect = [[_G.eq(_G.png_size(_G.shown), { 600, 150 })]],
      note = "the picture is 600x150",
    },

    -- a video without a sound track
    {
      lua = [[_G.forget(); _G.silent = _G.make_silent_video(); vim.cmd("edit " .. vim.fn.fnameescape(_G.silent))]],
      note = "a video with no sound track, as the current buffer",
    },
    { keys = ":Media waveform<CR>" },
    {
      wait = [[_G.noted("no audio stream in this file")]],
      timeout = 20000,
      note = "waveform says there is no sound track",
    },
    { expect = [[_G.shown == nil]], note = "and shows no picture" },

    -- a file that is not there
    { lua = [[_G.forget()]] },
    { keys = ":Media frame not_there.mp4<CR>" },
    {
      wait = [[#_G.warnings > 0]],
      timeout = 10000,
      note = "frame of a missing file says so at warning or error level",
    },
    {
      expect = [[_G.shown == nil and vim.api.nvim_get_mode().mode == "n"]],
      note = "no picture, the editor goes on",
    },
  },
  judge = {
    "the waveform of a 440 Hz sine is a flat band of one colour (#9cdcfe), the spectrogram one horizontal line near 440 Hz",
    "the line for a file without sound and for a missing file reads well",
  },
}
