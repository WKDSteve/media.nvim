-- The `.transcript.md` sidecar: path convention and document shape.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local sidecar = require("media.output.sidecar")

  H.eq(
    sidecar.path("/videos/talk.mp4"),
    "/videos/talk.mp4.transcript.md",
    "the suffix is appended to the full name, not swapped for the extension"
  )
  H.ok(
    sidecar.path("/videos/talk.mp4") ~= sidecar.path("/videos/talk.mov"),
    "two source extensions do not collide on one sidecar"
  )

  ---@type Media.Transcript
  local transcript = {
    engine = "whisper_cpp",
    model = "ggml-base.en.bin",
    lang = "en",
    duration = nil,
    segments = {
      { s = 0, e = 1, text = "Hello" },
      { s = 1, e = 2, text = "world." },
    },
    text = "Hello world.",
  }

  local content = sidecar.content("/videos/talk.mp4", transcript)
  H.match(content, "^# Transcript %— talk%.mp4", "the heading names the source file")
  H.match(content, "whisper_cpp %(ggml%-base%.en%.bin%)", "engine and model are both recorded")
  H.match(content, "\n%[00:00:00%] Hello\n", "a segment is a line with the time mark of its start")
  H.match(content, "\n%[00:00:01%] world%.\n", "the next one is on its own line")

  local long = sidecar.content("/v/a.mp4", {
    engine = "x",
    segments = {
      { s = 3725.9, e = 3730, text = "late\n\nline" },
      { s = 3731, e = 3732, text = "  " },
      { s = 3733, e = 3734, text = "last" },
    },
  })
  H.match(
    long,
    "\n%[01:02:05%] late line\n",
    "hours, whole seconds, a line break inside a segment is a space"
  )
  H.match(long, "\n%[01:02:13%] last\n", "an empty segment is left out")
  H.eq(select(2, long:gsub("%[%d%d:%d%d:%d%d%]", "")), 2, "two marks, no more")

  local flat = sidecar.content("/v/a.mp4", { engine = "x", segments = {}, text = "" })
  H.match(flat, "# Transcript", "a transcript without segments still gets its heading")
end
