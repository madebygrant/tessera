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
  schema.validateProfiles(C)

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

  -- Every screen the profile's `screens` list names is connected.
  C.profileFits = function(name)
    for _, ref in ipairs(C.profile(name).screens or {}) do
      if not core.findScreen(C.screens[ref]) then return false end
    end
    return true
  end

  -- The profile to run on the screens connected now: `preferred` if it fits,
  -- else defaultProfile, else the first fitting one by name. With none fitting,
  -- defaultProfile anyway, since slots fall back to the primary screen.
  C.bestProfile = function(preferred)
    if preferred and C.profiles[preferred] and C.profileFits(preferred) then
      return preferred
    end
    if C.profileFits(C.defaultProfile) then return C.defaultProfile end
    local names = {}
    for name in pairs(C.profiles) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      if C.profileFits(name) then return name end
    end
    return C.defaultProfile
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

-- Every name a profile refers to, checked at load. Otherwise a typo surfaces as
-- an error on a keypress, after the profile broadcast has already gone out and
-- left the modules disagreeing about which profile is live.
function schema.validateProfiles(C)
  assert(C.profiles, "tessera: config has no `profiles` block")
  assert(C.profiles[C.defaultProfile or false],
    "tessera: defaultProfile '" .. tostring(C.defaultProfile) .. "' is not a profile")

  for name, p in pairs(C.profiles) do
    local where = "tessera: profile '" .. name .. "' "
    local function slot(s, field)
      assert(C.slots[s or false], where .. field .. " names unknown slot '" .. tostring(s) .. "'")
    end
    local function app(a, field)
      assert(C.apps[a or false], where .. field .. " names unknown app '" .. tostring(a) .. "'")
    end

    assert(p.key, where .. "has no key")
    local sw = p.switcher
    assert(sw, where .. "has no switcher block")
    app(sw.anchor, "switcher.anchor")
    for _, field in ipairs({ "anchorSlot", "otherSlot", "fullSlot" }) do
      slot(sw[field], "switcher." .. field)
    end
    assert(type(sw.apps) == "table", where .. "switcher.apps must be a list")
    local listed = {}
    for _, ref in ipairs(sw.apps) do
      app(ref, "switcher.apps")
      listed[ref] = true
    end
    assert(sw.start == nil or listed[sw.start],
      where .. "starts on '" .. tostring(sw.start) .. "', which is not in its switcher apps")

    for _, item in ipairs(p.place or {}) do
      app(item.app, "place")
      slot(item.slot, "place")
    end
    for _, s in ipairs(p.slots or {}) do slot(s, "slots") end
    for _, ref in ipairs(p.screens or {}) do
      assert(C.screens[ref], where .. "screens names unknown screen '" .. tostring(ref) .. "'")
    end
  end
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
