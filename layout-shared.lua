-- layout-shared.lua
--
-- Pure utilities shared by the two feature modules: geometry, the frame clamp,
-- app/window lookup across processes, and the window registry and profile
-- broadcast they talk over instead of requiring each other. No config knowledge.

local core = {}

-- Falls back to the primary screen, so an unplugged monitor degrades instead
-- of erroring.
function core.resolveScreen(spec)
  if type(spec) == "function" then return spec() end
  if spec then
    for _, s in ipairs(hs.screen.allScreens()) do
      local name = s:name()
      if name and name:find(spec, 1, true) then return s end
    end
  end
  return hs.screen.primaryScreen()
end

-- A frame from fractions (0..1) of a screen's usable area.
--   inset = pixels carved off the screen first, for overlays macOS leaves out
--           of :frame() (Sketchybar).
--   gap   = pixels off EACH slot edge, so neighbours sit 2*gap apart. Absorbs
--           apps that snap slightly larger than their slot.
function core.frameFor(spec)
  local f = core.resolveScreen(spec.screen):frame()
  local i = spec.inset or {}
  local x0 = f.x + (i.left or 0)
  local y0 = f.y + (i.top or 0)
  local w0 = f.w - (i.left or 0) - (i.right or 0)
  local h0 = f.h - (i.top or 0) - (i.bottom or 0)
  local g = spec.gap or 0
  return {
    x = x0 + w0 * (spec.x or 0) + g,
    y = y0 + h0 * (spec.y or 0) + g,
    w = w0 * (spec.w or 1) - 2 * g,
    h = h0 * (spec.h or 1) - 2 * g,
  }
end

-- Pull a window back from its screen's RIGHT edge, so one that snaps wider than
-- its slot can't bleed onto the neighbouring screen. Vertical overflow is left
-- alone on purpose: falling off the bottom beats being pushed up into the slot
-- above, which would overlap a flush neighbour.
local function clampInto(win)
  local f = win:frame()
  local s = win:screen():frame()
  if f.x + f.w > s.x + s.w then
    win:setTopLeft({ x = s.x + s.w - f.w, y = f.y })
  end
end

-- Re-clamp on a delay as well: apps that snap to a cell grid (Ghostty) resize a
-- beat after setFrame returns, so the immediate clamp sees a stale size.
function core.setFrameClamped(win, target)
  win:setFrame(target)
  clampInto(win)
  hs.timer.doAfter(0.15, function() clampInto(win) end)
  hs.timer.doAfter(0.4, function() clampInto(win) end)
end

-- Empty suffix matches anything.
function core.endsWith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

-- True if a titled entry claims this title.
function core.endsWithAny(s, suffixes)
  for _, suffix in ipairs(suffixes or {}) do
    if core.endsWith(s, suffix) then return true end
  end
  return false
end

-- App name -> bundle id, learned once the app is seen running; later lookups
-- then take the indexed path instead of walking the process table.
local bundleIds = {}

-- EVERY process for an app. macOS hosts two whenever an entry's launch or
-- profileDir shells out to `open -na`, and hs.application.get returns only one
-- of them, so anything built on it silently misses the other's windows. Config
-- entries name apps rather than bundle ids, so the first call per app scans;
-- put a bundle id in the config to skip even that.
function core.apps(name)
  local found = hs.application.applicationsForBundleID(bundleIds[name] or name)
  if #found > 0 then return found end
  local out = {}
  for _, a in ipairs(hs.application.runningApplications()) do
    if a:name() == name or a:bundleID() == name then
      out[#out + 1] = a
      bundleIds[name] = a:bundleID()
    end
  end
  return out
end

-- The process to treat as "the" app: most standard windows. A stray second
-- instance usually has one or none, so this lands on the real one.
function core.primaryApp(name)
  local best, most = nil, -1
  for _, a in ipairs(core.apps(name)) do
    local n = 0
    for _, w in ipairs(a:allWindows()) do
      if w:isStandard() then n = n + 1 end
    end
    if n > most then best, most = a, n end
  end
  return best
end

-- Every standard window of an app, across all its processes.
function core.appWindows(name)
  local wins = {}
  for _, a in ipairs(core.apps(name)) do
    for _, w in ipairs(a:allWindows()) do
      if w:isStandard() then wins[#wins + 1] = w end
    end
  end
  return wins
end

-- Menu item first, since Cmd+N needs the app activated. This is the only way to
-- get a second window out of a running app; launchOrFocus just focuses one.
function core.openNewWindow(app)
  local menus = {
    { "File", "New Window" },
    { "File", "New window" },
    { "Shell", "New Window" },   -- Terminal
    { "Window", "New Window" },
  }
  for _, path in ipairs(menus) do
    if app:findMenuItem(path) then
      app:selectMenuItem(path)
      return
    end
  end
  app:activate()
  hs.eventtap.keyStroke({ "cmd" }, "n", 0, app)
end

-- Stable key for a placed window, built identically on both sides of the registry.
function core.entryKey(app, suffix)
  return app .. "\0" .. (suffix or "")
end

-- One module publishes a live window under an entryKey; the other resolves it.
local registry = {} -- entryKey -> window id

function core.publishWindow(key, win)
  registry[key] = win and win:id() or nil
end

function core.window(key)
  local id = registry[key]
  return id and hs.window.get(id) or nil
end

-- window-layout announces the profile it applied; the switcher retargets to it.
-- Same decoupling as the registry: neither module requires the other.
local profileHandlers = {}
local activeProfile = nil

function core.onProfile(fn)
  profileHandlers[#profileHandlers + 1] = fn
end

function core.setProfile(name)
  if name == activeProfile then return end
  activeProfile = name
  for _, fn in ipairs(profileHandlers) do fn(name) end
end

function core.profile()
  return activeProfile
end

return core
