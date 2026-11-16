-- Feature media.play (TESTS/sheets/features.lua): `:Media window` starts mpv on the buffer's video, `:Media play` hands it to the configured player, and a `bin.mpv` that names nothing ends in one readable line instead
-- of an error (media.nvim 'fix(player)': an mpv that cannot be started). mpv is a recording stand-in (`fakes`): the
-- sheet proves what would be started; that a window opens, plays with sound and closes again is a person's (the live
-- plan's section 6, the manual line). `at=` is not read from the recorded argv: the Windows stand-in (a .cmd file)
-- splits `--start=1` at the `=`; that `at=` reaches mpv as `--start=` is usrcmds_window_spec's.
return {
  id = "media.play",
  feature = "media.play",
  title = ":Media window and :Media play start mpv with the file, a missing mpv is one readable line",
  task = "media.nvim/live-plan-media-live-testing-plan-sortieren-erledigtes-abhak",
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
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot(); package.loaded["media"].play = require("media.core.play").play; require("media").setup({ player = "mpv" })]],
      note = "the test video, the real :Media play (not the recorder of boot), player = mpv",
    },

    -- :Media window
    { keys = ":Media window<CR>" },
    { wait = [[#_G.calls("mpv") == 1]], timeout = 10000, note = "mpv is started" },
    {
      expect = [[vim.uv.fs_realpath(_G.calls("mpv")[1].argv[#_G.calls("mpv")[1].argv]) == vim.uv.fs_realpath(_G.video)]],
      note = "on the buffer's video",
    },

    -- :Media play
    { keys = ":Media play<CR>" },
    {
      wait = [[#_G.calls("mpv") == 2]],
      timeout = 10000,
      note = "the configured player is started",
    },
    {
      expect = [[vim.uv.fs_realpath(_G.calls("mpv")[2].argv[#_G.calls("mpv")[2].argv]) == vim.uv.fs_realpath(_G.video)]],
      note = "with the file",
    },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },

    -- an mpv that is not there
    {
      lua = [[_G.forget(); require("media").setup({ bin = { mpv = _G.dir .. "/no-such-mpv" } })]],
      note = "bin.mpv points to nothing now",
    },
    { keys = ":Media window<CR>" },
    {
      wait = [[table.concat(_G.warnings, "\n"):find("could not start mpv", 1, true) ~= nil]],
      timeout = 10000,
      note = "one line says mpv could not be started",
    },
    {
      expect = [[#_G.calls("mpv") == 2 and vim.api.nvim_get_mode().mode == "n"]],
      note = "nothing started, no hang",
    },
  },
  manual = {
    "With the real mpv: :Media window opens a window that plays picture and sound, and :qa closes it again",
  },
}
