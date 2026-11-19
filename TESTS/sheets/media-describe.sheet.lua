-- Feature media.describe (TESTS/sheets/features.lua): the record of a media file (duration, codecs, size, streams) by
-- the key <leader>Mp, by `:Media probe` on the buffer's file and on a named one, and by the bare `:Media`. ffprobe runs
-- for real on the test video of _helpers.lua (ffmpeg is installed on every hosted leg, `packages` in .testing.lua).
return {
  id = "media.describe",
  feature = "media.describe",
  title = "<leader>Mp, :Media probe [path] and :Media describe a video: size, codecs, duration",
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
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]],
      note = "the test video (320x240, h264, a sine tone) as the current buffer",
    },

    { keys = [[\Mp]] },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "<leader>Mp opens the record of the buffer's file",
    },
    {
      expect = [[_G.floattext():find("h264", 1, true) ~= nil and _G.floattext():find("aac", 1, true) ~= nil]],
      note = "with the video and the audio codec",
    },
    { keys = "q" },
    { expect = [[_G.floattext() == ""]], note = "q closes it" },

    -- by name, from another buffer
    { lua = [[vim.cmd("enew")]], note = "an empty buffer now" },
    {
      lua = [[vim.cmd("Media probe " .. vim.fn.fnameescape(_G.video))]],
      note = ":Media probe <path>",
    },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "the named file is described",
    },
    {
      expect = [[(function() for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.inspect(vim.api.nvim_win_get_config(w).title or ""):find("clip.mp4", 1, true) then return true end end return false end)()]],
      note = "its window is titled with the file's name",
    },
    { keys = "q" },

    -- the bare verb
    { lua = [[_G.back_to_video()]], note = "back in the video's buffer" },
    { keys = ":Media<CR>" },
    {
      wait = [[_G.floattext():find("320x240", 1, true)]],
      timeout = 10000,
      note = "bare :Media describes the buffer's file as well",
    },
    { keys = "q" },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
  judge = { "the record reads well: aligned rows, a duration in minutes and seconds, a size in MB" },
}
