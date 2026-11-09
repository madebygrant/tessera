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
  local screen = win:screen()
  if not screen then return end -- entirely off every screen
  local f = win:frame()
  local s = screen:frame()
  if f.x + f.w > s.x + s.w then
    win:setTopLeft({ x = s.x + s.w - f.w, y = f.y })
  end
end

-- Re-clamp on a delay as well: apps that snap to a cell grid (Ghostty) resize a
-- beat after setFrame returns, so the immediate clamp sees a stale size.
-- Unanimated, because during an animation frame() reports the target and the
-- early clamps would see nothing to fix.
function core.setFrameClamped(win, target)
  if win:isMinimized() then win:unminimize() end
  win:setFrame(target, 0)
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

-- Accessibility only lists windows on the current Space, so a window parked on
-- another one looks missing and would get a duplicate. CoreGraphics sees every
-- Space but, without Screen Recording, no titles: it can only say one exists.
function core.hasWindowOnOtherSpace(name)
  local pids, seen = {}, {}
  for _, a in ipairs(core.apps(name)) do
    pids[a:pid()] = true
    for _, w in ipairs(a:allWindows()) do
      local id = w:id()
      if id then seen[id] = true end
    end
  end
  if not next(pids) then return false end
  for _, info in ipairs(hs.window.list(true) or {}) do
    local b = info.kCGWindowBounds
    -- Size floor skips the tiny utility surfaces some apps keep at layer 0.
    -- Onscreen ones are on this Space; AX missing them means no permission.
    if pids[info.kCGWindowOwnerPID] and info.kCGWindowLayer == 0
      and not info.kCGWindowIsOnscreen
      and not seen[info.kCGWindowNumber]
      and b and b.Width >= 100 and b.Height >= 100 then
      return true
    end
  end
  return false
end

-- From the CoreGraphics list, so no Accessibility call into a possibly hung app.
function core.hasWindowIn(pid, frame)
  for _, info in ipairs(hs.window.list(true) or {}) do
    local b = info.kCGWindowBounds
    if info.kCGWindowOwnerPID == pid and info.kCGWindowLayer == 0 and b then
      local cx, cy = b.X + b.Width / 2, b.Y + b.Height / 2
      if cx >= frame.x and cx <= frame.x + frame.w
        and cy >= frame.y and cy <= frame.y + frame.h then
        return true
      end
    end
  end
  return false
end

-- Why tessera shouldn't launch an app it found no window for, or nil. Without
-- Accessibility every window looks missing, so that's checked first.
function core.launchBlocker(name)
  if not hs.accessibilityState() then
    return "Hammerspoon has lost Accessibility permission. Re-enable it in System Settings"
  end
  if core.hasWindowOnOtherSpace(name) then
    return name .. " has a window on another Space; not opening another"
  end
  return nil
end

-- Handles are held until exit: an unreferenced hs.task can be collected
-- mid-flight.
local tasks = {}
local function run(path, args)
  local task
  task = hs.task.new(path, function() tasks[task] = nil end, args)
  tasks[task] = true
  if not task:start() then tasks[task] = nil end
end

-- An entry's own launch recipe, run without blocking Hammerspoon. False when it
-- has none and the caller should open the app its own way.
function core.spawn(entry)
  if entry.launch then
    run("/bin/sh", { "-c", entry.launch })
    return true
  end
  if entry.profileDir then
    run("/usr/bin/open", {
      "-na", entry.app, "--args",
      "--profile-directory=" .. entry.profileDir, "--new-window",
    })
    return true
  end
  return false
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
-- Keyed by pid as well as id: hs.window.get(id) walks every window of every
-- app, tens of ms per call, and this runs on each app activation.
local registry = {} -- entryKey -> { pid, id }

function core.publishWindow(key, win)
  local app = win and win:application()
  registry[key] = app and { pid = app:pid(), id = win:id() } or nil
end

function core.window(key)
  local r = registry[key]
  if not r then return nil end
  local app = hs.application.applicationForPID(r.pid)
  if not app then return nil end
  for _, w in ipairs(app:allWindows()) do
    if w:id() == r.id then return w end
  end
  return nil
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

-- Fired after window-layout has placed a profile's windows, including on a
-- re-press of the active profile, which setProfile ignores.
local appliedHandlers = {}

function core.onApplied(fn)
  appliedHandlers[#appliedHandlers + 1] = fn
end

function core.applied(name)
  for _, fn in ipairs(appliedHandlers) do fn(name) end
end

return core
