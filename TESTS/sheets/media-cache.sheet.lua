-- Feature media.cache (TESTS/sheets/features.lua): a still is rendered once and then answered from the cache, and
-- `:Media cache clear` throws the cache away (the next still is rendered again). ffmpeg runs for real on the test video
-- of _helpers.lua; the picture viewer is the recorder of `boot()`.
return {
  id = "media.cache",
  feature = "media.cache",
  title = "A second :Media frame comes from the cache, :Media cache clear removes the stills",
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
      note = "the test video, the cache in a temp directory (XDG_CACHE_HOME)",
    },

    { keys = ":Media frame at=1 width=160<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 15000, note = "a still is rendered" },
    {
      lua = [[_G.first = _G.shown; _G.first_mtime = vim.inspect(vim.uv.fs_stat(_G.first).mtime); _G.forget()]],
    },
    { keys = ":Media frame at=1 width=160<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 15000, note = "the same still again" },
    { expect = [[_G.shown == _G.first]], note = "the same file, from the cache" },
    {
      expect = [[vim.inspect(vim.uv.fs_stat(_G.first).mtime) == _G.first_mtime]],
      note = "not written again",
    },

    { lua = [[_G.forget()]] },
    { keys = ":Media cache clear<CR>" },
    {
      expect = [[_G.noted("cached still(s) removed") and not _G.noted("0 cached")]],
      note = "one line says how many were removed",
    },
    { expect = [[vim.fn.filereadable(_G.first) == 0]], note = "the still is gone from the disk" },

    { lua = [[_G.forget()]] },
    { keys = ":Media frame at=1 width=160<CR>" },
    { wait = [[_G.shown ~= nil]], timeout = 15000, note = "asked again" },
    { expect = [[vim.fn.filereadable(_G.shown) == 1]], note = "it is rendered anew and exists" },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
}
