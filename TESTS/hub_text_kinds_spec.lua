-- media.hub.text routes tool, modes and run through one KIND_HANDLERS table, so a
-- kind is one entry (`register`) and the three questions cannot disagree.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch

---@param H table
return function(H)
  local text = require("media.hub.text")

  H.ok(type(text.register) == "function", "register exists")

  -- A registered kind answers all three questions from its own handler.
  local ran
  text.register("note", {
    tool = function()
      return { ok = true, tool = "notetool" }
    end,
    modes = function()
      return { "buffer" }
    end,
    run = function(path, kind, _opts, callback)
      ran = { path = path, kind = kind }
      callback({ kind = "note", text = "hello", tool = "notetool" }, nil)
      return nil
    end,
  })

  H.eq(text.tool("note").tool, "notetool", "tool() asks the registered handler")
  H.eq_list(text.modes("note"), { "buffer" }, "modes() asks the registered handler")

  -- Routing by kind goes through media.hub.kinds; stub it for the fake kind.
  local kinds = require("media.hub.kinds")
  local orig_of = kinds.of
  kinds.of = function(path)
    if path:match("%.note$") then return "note" end
    return orig_of(path)
  end
  local got
  local good, err = pcall(function()
    text.run("a.note", nil, function(result)
      got = result
    end)
  end)
  kinds.of = orig_of
  H.ok(good, "run() reaches the handler without error: " .. tostring(err))
  H.eq(ran and ran.path, "a.note", "run() hands the path over")
  H.eq(ran and ran.kind, "note", "run() hands the kind over")
  H.eq(got and got.text, "hello", "run() returns the handler's result")

  -- An unregistered kind keeps the old answers.
  H.eq(text.tool("nonsense").ok, false, "unknown kind: tool is not ok")
  H.eq_list(text.modes("nonsense"), { "buffer", "sidecar" }, "unknown kind: file modes")

  -- The if chain is gone.
  local path = vim.api.nvim_get_runtime_file("lua/media/hub/text.lua", false)[1]
  local src = table.concat(vim.fn.readfile(path), "\n")
  H.ok(src:find("KIND_HANDLERS", 1, true) ~= nil, "handler table exists")
  H.ok(src:find('if kind == "image" then', 1, true) == nil, "no per-kind if chain on image")
  H.ok(src:find('if kind == "pdf" then', 1, true) == nil, "no per-kind if chain on pdf")
end
