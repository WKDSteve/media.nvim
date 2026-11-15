-- Feature media.tree-badge (TESTS/sheets/features.lua): in the real own tree of filetree.nvim a recording with a
-- transcript next to it (`<file>.transcript.md`) carries the badge `transcript`; a recording without one, the
-- transcript itself and a folder show nothing. The badges are virtual text the tree places while it draws, so the
-- sheet reads the screen. That the badge follows a transcript media.nvim writes itself is the sheet
-- media.tree-transcribe. (A transcript another program writes gets its badge with the next scan: after a file
-- operation of the tree or a change of its root, not by reading the folders again.)
-- filetree.nvim and ui.nvim come from .deps/ (CI) or beside this repository; without them the sheet is a reported
-- skip (n/a), never green.
return {
  id = "media.tree-badge",
  feature = "media.tree-badge",
  title = "media.nvim: a recording with a transcript next to it carries a badge in the tree",
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
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.tree_boot()]],
      note = "the project recordings, media.nvim, the own tree on the left",
    },
    {
      lua = [[_G.on("talks/standup.mp4")]],
      note = "open talks in the tree, the cursor on the video without a transcript",
    },
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
    { expect = [[_G.eq(_G.row("talks"), "  ▾ talks/")]], note = "a folder shows nothing" },
    { screen = "badge", note = "the tree with the badge" },

    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
  judge = {
    "The badge sits at the right edge of the tree and reads as a note, not as an error",
  },
}
