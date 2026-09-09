-- schema.lua
--
-- The accessors and feature checks every config needs. They live here, not in
-- the config file, so a fix reaches every config and the config stays data.

local core = require("tessera.layout-shared")

local schema = {}

function schema.attach(C)
  -- Hammerspoon binds a nil modifier as the BARE key, so a missing layer would
  -- silently hand the number row to tessera. Name the gap at load instead.
  assert(C.keys, "tessera: config has no `keys` block")
  for _, layer in ipairs({ "switcher", "maximize" }) do
    assert(C.keys[layer], "tessera: config.keys." .. layer .. " is missing")
  end
  for name, p in pairs(C.profiles or {}) do
    assert(p.modifier or C.keys.profile, "tessera: profile '" .. name ..
      "' has no modifier of its own and config.keys.profile is missing")
  end
  if schema.enabled(C, "slotMove") then
    assert(C.keys.slotMove, "tessera: slotMove is on but config.keys.slotMove is missing")
  end

  C.slot = function(name)
    local s = C.slots[name]
    assert(s, "unknown slot: " .. tostring(name))
    return core.frameFor({
      screen = C.screens[s.screen] or s.screen,
      inset = C.screenInsets and C.screenInsets[s.screen],
      gap = C.gap,
      x = s.x, y = s.y, w = s.w, h = s.h,
    })
  end

  C.app = function(ref)
    local a = C.apps[ref]
    assert(a, "unknown app: " .. tostring(ref))
    return a
  end

  C.profile = function(name)
    local p = C.profiles[name]
    assert(p, "unknown profile: " .. tostring(name))
    return p
  end

  -- Title suffixes other entries claim for the same app, so an untitled entry
  -- can skip their windows.
  C.reservedSuffixes = function(appName)
    local out = {}
    for _, a in pairs(C.apps) do
      if a.app == appName and a.titleSuffix then out[#out + 1] = a.titleSuffix end
    end
    return out
  end

  return C
end

-- One rule for every optional feature: the block has to be there, and it can
-- turn itself off. No block means off, so the config lists what's running.
function schema.enabled(C, name)
  local block = C[name]
  if block == nil then return false end
  assert(type(block) == "table",
    "tessera: config." .. name .. " must be a table, e.g. { enabled = true }")
  return block.enabled ~= false
end

return schema
