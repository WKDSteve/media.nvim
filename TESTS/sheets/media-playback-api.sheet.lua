-- Feature media.playback-api (TESTS/sheets/features.lua): what a plugin that plays a video as text (hover.nvim) asks of
-- media.nvim — a run of stills (`frames`, ffmpeg for real on the test video of _helpers.lua) and the sound beside it
-- (`audio`, an mpv driven over its IPC socket). mpv is a recording stand-in (`fakes`): it records its arguments and
-- ends, it opens no socket, so the sheet proves what would be started and that the caller is told, after the bounded
-- retry of two seconds, to carry on without sound (and on Windows the tree kill of `media.core.proc` runs). That
-- the real mpv plays, pauses and stops the sound is a person's (`manual`).
return {
  id = "media.playback-api",
  feature = "media.playback-api",
  title = "media.frames renders a run of stills, media.audio starts mpv and gives up without a socket",
  engine = "rpc",
  sizes = { { rows = 40, cols = 120 } },
  fakes = { "mpv" },
  requires = {
    {
      lua = [[vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1]],
      reason = "ffmpeg and ffprobe are not installed",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]],
      note = "the test video (3 s at 10 fps)",
    },

    -- frames
    {
      lua = [[require("media").frames(_G.video, { from = 0, count = 4 }, function(pngs, err) _G.run = { pngs = pngs, err = err } end)]],
      note = "a run of four stills from the start, as a consumer asks for it",
    },
    { wait = [[_G.run ~= nil]], timeout = 20000, note = "the callback comes" },
    {
      expect = [[_G.run.err == nil and #_G.run.pngs == 4]],
      note = "with four stills and no error",
    },
    {
      expect = [[vim.iter(_G.run.pngs):all(function(p) return vim.fn.filereadable(p) == 1 and _G.png_size(p)[2] > 0 end)]],
      note = "PNGs that exist",
    },

    -- audio
    {
      lua = [[require("media").audio(_G.video, { at = 0 }, function(handle, err) _G.sound = { handle = handle, err = err } end)]],
      note = "the sound for the run, from the start",
    },
    { wait = [[#_G.calls("mpv") == 1]], timeout = 10000, note = "mpv is started" },
    {
      expect = [[vim.iter(_G.calls("mpv")[1].argv):any(function(a) return a:find("clip.mp4", 1, true) ~= nil end)]],
      note = "on the video",
    },
    { wait = [[_G.sound ~= nil]], timeout = 10000, note = "the callback comes" },
    {
      expect = [[_G.sound.handle == nil and tostring(_G.sound.err):find("IPC socket never came up", 1, true) ~= nil]],
      note = "without a handle: the stand-in opened no socket, and the error says so",
    },
    { expect = [[vim.api.nvim_get_mode().mode == "n"]], note = "no hang, the editor goes on" },
  },
  manual = {
    "In hover.nvim with the real mpv: a video hover plays the stills with sound, and closing it stops the sound",
  },
}
