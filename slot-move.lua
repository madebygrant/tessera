-- slot-move.lua
--
-- Drops the focused window into one of the active profile's slots. The switcher
-- moves apps it knows about; this moves whatever you happen to be looking at.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

local M = {}

local slots = {}

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

-- A profile's `slots` list is the key order when it has one. Otherwise take the
-- slots its `place` entries use, first appearance wins, which is already the
-- order someone reading the profile would expect. Copied either way, so nothing
-- here ends up aliasing the config's own tables.
local function slotsFor(name)
  local profile = config.profile(name)
  if profile.slots then return copy(profile.slots) end

  local seen, out = {}, {}
  for _, item in ipairs(profile.place or {}) do
    if not seen[item.slot] then
      seen[item.slot] = true
      out[#out + 1] = item.slot
    end
  end
  return out
end

local function moveTo(index)
  local slot = slots[index]
  if not slot then return end
  local win = hs.window.focusedWindow()
  if win then core.setFrameClamped(win, config.slot(slot)) end
end

-- Widest slot list across all profiles, so a profile switch never rebinds.
-- Same trick as the switcher's number keys. Checks the names on the way past:
-- otherwise a typo only surfaces as an error dialog on every keypress.
local function maxSlots()
  local n = 0
  for name in pairs(config.profiles) do
    local list = slotsFor(name)
    for _, slot in ipairs(list) do
      assert(config.slots[slot],
        "tessera: profile '" .. name .. "' lists unknown slot '" .. tostring(slot) .. "'")
    end
    if #list > n then n = #list end
  end
  return n
end

for i = 1, maxSlots() do
  hs.hotkey.bind(config.keys.slotMove, tostring(i), function() moveTo(i) end)
end

slots = slotsFor(config.defaultProfile)
core.onProfile(function(name) slots = slotsFor(name) end)

M.slots = function() return copy(slots) end

return M
