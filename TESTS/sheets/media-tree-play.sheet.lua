-- Feature media.tree-actions (TESTS/sheets/features.lua), play: a project with recordings in the real own tree of
-- filetree.nvim. "Play this recording in a player" from the context menu of a video, and the configured key on
-- an audio file, each start the configured player with exactly that file. The player is a recording stand-in
-- (`fakes`): the sheet proves what would be started, not that a film plays (a manual line).
-- filetree.nvim and ui.nvim come from .deps/ (CI) or beside this repository; without them the sheet is a reported
-- skip (n/a), never green.
return {
  id = "media.tree-play",
  feature = "media.tree-actions",
  title = "media.nvim: play from the menu and the key of a media node in the tree starts the player with that file",
  task = "images.nvim/own-tree-feature-sheets-images-media-pickers",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  fakes = { "mpv" },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.tree_boot({ player = "mpv" })]],
      note = "the project recordings, media.nvim with player = mpv, the own tree on the left",
    },
    {
      lua = [[_G.on("talks/standup.mp4")]],
      note = "open talks in the tree, the cursor on the video",
    },

    -- from the menu
    { lua = [[_G.right_click("talks/standup.mp4")]], note = "a right click on the video" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Play this recording in a player")]],
      note = "it offers to play the recording",
    },
    { keys = "<CR>", note = "pick the entry" },
    { wait = [[#_G.calls("mpv") == 1]], timeout = 10000, note = "the player is started" },
    {
      expect = [[_G.eq(#_G.calls("mpv")[1].argv, 1) and _G.eq(vim.uv.fs_realpath(_G.calls("mpv")[1].argv[1]), vim.uv.fs_realpath(_G.rec .. "/talks/standup.mp4"))]],
      note = "with the video of the node as its only argument",
    },
    { lua = [[_G.close_floats()]] },

    -- from the key
    { lua = [[_G.on("audio/jingle.mp3")]], note = "the cursor on the audio file" },
    { keys = "gmp", note = "the key the config gave the action" },
    { wait = [[#_G.calls("mpv") == 2]], timeout = 10000, note = "the player is started again" },
    {
      expect = [[_G.eq(vim.uv.fs_realpath(_G.calls("mpv")[2].argv[1]), vim.uv.fs_realpath(_G.rec .. "/audio/jingle.mp3"))]],
      note = "with the audio file",
    },

    -- a file that is no recording
    { lua = [[_G.on("README.md")]], note = "the cursor on a file that is no recording" },
    { lua = [[_G.right_click("README.md")]] },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "its menu is open" },
    {
      expect = [[not _G.menu_on("Play this recording in a player") and not _G.menu_on("Transcribe this recording")]],
      note = "without the actions of media.nvim",
    },
    { lua = [[_G.close_floats(); _G.tree()]] },
    { keys = "gmp", ignore_errmsg = true, note = "the key on it" },
    { lua = [[vim.wait(300)]] },
    { expect = [[_G.eq(#_G.calls("mpv"), 2)]], note = "starts nothing" },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
  manual = {
    "In the real editor with a real player configured (mpv, vlc): the entry and the key open the recording in the player, with sound and picture",
    "Without `player` in the config the recording opens in what the system opens it with",
  },
}
