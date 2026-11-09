#!/usr/bin/env bash
# Runs inside the live Hammerspoon so the hs.* globals exist.
set -u
cd "$(dirname "$0")"
HS=$(command -v hs) || HS=/opt/homebrew/bin/hs
[ -x "$HS" ] || { echo "hs CLI not found; run hs.ipc.cliInstall() in Hammerspoon" >&2; exit 2; }

"$HS" -t 10 -c '
local root = "'"$PWD"'/"
local fail = false
local function report(name, ok, err)
  print((ok and "ok    " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))))
  fail = fail or not ok
end
for _, f in ipairs({ "init.lua", "layout-shared.lua", "layout-workspace.lua",
                     "schema.lua", "slot-move.lua", "window-layout.lua",
                     "overlay.lua", "picker.lua", "tessera-config.example.lua" }) do
  local fn, err = loadfile(root .. f)
  report(f, fn ~= nil, err)
end
local schema = dofile(root .. "schema.lua")
for _, f in ipairs({ root .. "tessera-config.example.lua",
                     root .. "config.lua",
                     os.getenv("HOME") .. "/.hammerspoon/tessera-config.lua" }) do
  if io.open(f) then
    local ok, err = pcall(function() schema.attach(dofile(f)) end)
    report("schema: " .. f, ok, err)
  end
end
if fail then error("check failed", 0) end
print("all good")
'
