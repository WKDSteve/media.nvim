-- Feature media.tree-actions (TESTS/sheets/features.lua), contact sheet: "Show the contact sheet of this video" from
-- the context menu of a video in the real own tree of filetree.nvim, and the configured key. ffmpeg is the real
-- one, on a three second test video it made itself: the sheet notes the ffmpeg call (which file, the tile filter)
-- and checks that a PNG that exists is handed to the picture viewer (a recorder: a headless child draws none).
-- An audio file has no contact sheet. Needs ffmpeg and ffprobe (the workflow installs them), filetree.nvim and
-- ui.nvim (.deps/ on CI, else beside this repository).
return {
  id = "media.tree-sheet",
  feature = "media.tree-actions",
  title = "media.nvim: contact sheet from the menu and the key of a video node in the tree renders and shows it",
  task = "media.nvim/abnahme-media-actions-in-the-own-tree",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[vim.fn.executable("ffmpeg") == 1 and vim.fn.executable("ffprobe") == 1]],
      reason = "ffmpeg and ffprobe are not installed",
    },
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.tree_boot({ video = true }); _G.watch_spawns()]],
      note = "the project recordings with a real test video, media.nvim, the own tree on the left",
    },
    {
      lua = [[_G.on("talks/standup.mp4")]],
      note = "open talks in the tree, the cursor on the video",
    },

    -- from the menu
    { lua = [[_G.right_click("talks/standup.mp4")]], note = "a right click on the video" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Show the contact sheet of this video")]],
      note = "it offers the contact sheet",
    },
    { keys = "<CR>", note = "pick the entry" },
    {
      wait = [[_G.shown ~= nil]],
      timeout = 30000,
      note = "the contact sheet is rendered and handed to the viewer",
    },
    {
      expect = [[_G.shown:match("%.png$") ~= nil and vim.fn.filereadable(_G.shown) == 1 and vim.fn.getfsize(_G.shown) > 0]],
      note = "a PNG that exists",
    },
    {
      expect = [[_G.spawn_of("ffmpeg"):find("standup.mp4", 1, true) ~= nil and _G.spawn_of("ffmpeg"):find("tile=", 1, true) ~= nil]],
      note = "made by ffmpeg from the video of the node, with the tile filter",
    },
    { lua = [[_G.close_floats(); _G.shown = nil; _G.spawned = {}]] },

    -- from the key (the picture comes from the cache now: no second render)
    { lua = [[_G.on("talks/standup.mp4")]] },
    { keys = "gms", note = "the key the config gave the action" },
    { wait = [[_G.shown ~= nil]], timeout = 30000, note = "the contact sheet is shown again" },
    { lua = [[_G.close_floats(); _G.shown = nil; _G.spawned = {}]] },

    -- an audio file has no contact sheet
    { lua = [[_G.on("audio/jingle.mp3")]], note = "the cursor on the audio file" },
    { lua = [[_G.right_click("audio/jingle.mp3")]] },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "its menu is open" },
    {
      expect = [[_G.menu_on("Play this recording in a player") and not _G.menu_on("Show the contact sheet of this video")]],
      note = "with play, without the contact sheet",
    },
    { lua = [[_G.close_floats(); _G.tree()]] },
    { keys = "gms", ignore_errmsg = true, note = "the key on it" },
    { lua = [[vim.wait(300)]] },
    {
      expect = [[_G.shown == nil and _G.spawn_of("ffmpeg") == ""]],
      note = "renders nothing",
    },
    { expect = [[_G.eq(_G.warnings, {})]], note = "nothing was said at warning level" },
  },
  manual = {
    "In the real editor (a terminal that draws pictures, images.nvim installed): the contact sheet of a real film appears as a picture, the tiles in the order of the film and not black",
  },
}
