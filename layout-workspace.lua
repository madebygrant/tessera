-- layout-workspace.lua
--
-- The half-screen switcher: pins an anchor app to one slot and cycles other
-- apps through a second one. Which apps and slots come from the active profile.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

local M = {}

-- How long to keep chasing a launching app's window, and how often to look.
local launchTimeout = 5.0
local pollInterval = 0.2

local keys = config.switcher -- the hotkey layer; targets come from the profile

-- Retargeted by useProfile() whenever the active profile changes.
local sw          -- the active profile's switcher block
local anchorEntry
local workspace = {}
local currentIndex = 1

-- One in-flight poller per entry, so rapid re-switches don't stack timers all
-- racing to place the same window.
local pending = {}

local function entryKey(entry)
  return core.entryKey(entry.app, entry.titleSuffix)
end

local function place(win, slotName)
  core.setFrameClamped(win, config.slot(slotName))
end

-- Publish to the registry so a repeat press, and window-layout, reuse this one.
local function track(key, win)
  core.publishWindow(key, win)
end

-- The standard window whose title ends with `suffix` (Helium "Development").
local function titledWindow(appName, suffix)
  for _, w in ipairs(core.appWindows(appName)) do
    if core.endsWith(w:title() or "", suffix) then return w end
  end
  return nil
end

-- A window for an UNTITLED entry: anything a titled sibling hasn't claimed.
-- Prefers each process's main window, since appWindows order is only
-- incidentally z-order within a process and undefined across two.
local function plainWindow(appName)
  local reserved = config.reservedSuffixes(appName)
  -- isStandard mirrors appWindows, so this can't pick a dialog the scan skips.
  local function claimable(w)
    return w and w:isStandard() and not core.endsWithAny(w:title() or "", reserved)
  end
  for _, a in ipairs(core.apps(appName)) do
    local main = a:mainWindow()
    if claimable(main) then return main end
  end
  for _, w in ipairs(core.appWindows(appName)) do
    if claimable(w) then return w end
  end
  return nil
end

-- profileDir opens a Chromium profile in its own window; launch is raw shell.
local function launchEntry(entry)
  if entry.launch then
    hs.execute(entry.launch)
  elseif entry.profileDir then
    hs.execute(string.format(
      '/usr/bin/open -na %q --args --profile-directory=%q --new-window',
      entry.app, entry.profileDir
    ))
  else
    hs.application.open(entry.app, 0, true)
  end
end

-- Place an entry's window in `slotName`, launching the app if needed. Never
-- opens a second window for a running app -- that's window-layout's job.
--   titleSuffix -> reuse the SPECIFIC window whose title matches.
--   remember    -> record the window in the registry (cycled apps), vs not
--                  (the anchor, which is just whatever window the app has).
local function placeApp(entry, slotName, remember, focus)
  local shouldFocus = focus ~= false
  local appName = entry.app
  local key = entryKey(entry)

  -- Cancel any poller already chasing this entry; newest call wins.
  if pending[key] then
    pending[key]:stop()
    pending[key] = nil
  end

  if entry.titleSuffix then
    local existing = titledWindow(appName, entry.titleSuffix)
    if existing then
      place(existing, slotName)
      if shouldFocus then existing:focus() end
      track(key, existing)
      return
    end
    launchEntry(entry)
    local elapsed = 0
    pending[key] = hs.timer.doUntil(
      function() return elapsed >= launchTimeout end,
      function(timer)
        elapsed = elapsed + pollInterval
        local w = titledWindow(appName, entry.titleSuffix)
        if w then
          place(w, slotName)
          if shouldFocus then w:focus() end
          track(key, w)
          timer:stop()
          pending[key] = nil
        end
      end,
      pollInterval
    )
    return
  end

  -- Adopt an existing window rather than opening another: the registry is empty
  -- after a reboot, and an app launched at login used to get a second window
  -- beside the one it already had.
  local win = (remember and core.window(key)) or plainWindow(appName)
  if win then
    place(win, slotName)
    if shouldFocus then win:focus() end
    if remember then track(key, win) end
    return
  end

  -- Not running (or no window yet): launch and grab its first window.
  if #core.apps(appName) == 0 then
    hs.application.open(appName, 0, true)
  end

  local elapsed = 0
  pending[key] = hs.timer.doUntil(
    function() return elapsed >= launchTimeout end,
    function(timer)
      elapsed = elapsed + pollInterval
      local w = plainWindow(appName)
      if w then
        place(w, slotName)
        if shouldFocus then w:focus() end
        if remember then track(key, w) end
        timer:stop()
        pending[key] = nil
      end
    end,
    pollInterval
  )
end

local function placeAnchor(focus)
  placeApp(anchorEntry, sw.anchorSlot, false, focus)
end

-- Whether the cycled app covers the anchor. A switch restores the split.
local maximized = false

-- Sketchybar readout. Absent config means on-if-installed, so a machine with a
-- bar gets one without opting in; `enabled = false` is the opt-out.
local barConfig = config.sketchybar or {}
local barEvent = barConfig.event or "tessera_switcher"

-- Sketchybar's own PATH isn't Hammerspoon's, so find the binary rather than
-- shelling out by name. nil = disabled or absent, and every push is a no-op.
local sketchybar = (function()
  if barConfig.enabled == false then return nil end
  if barConfig.bin then
    if hs.fs.attributes(barConfig.bin) then return barConfig.bin end
    print("tessera: config.sketchybar.bin '" .. barConfig.bin .. "' not found; readout off")
    return nil
  end
  for _, path in ipairs({ "/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar" }) do
    if hs.fs.attributes(path) then return path end
  end
  return nil
end)()

-- Held until exit: an unreferenced hs.task can be collected mid-flight, which
-- showed up as the bar updating on only some switches.
local barTasks = {}

-- Fire-and-forget: a stale or absent bar must never block a window switch.
-- `focused` says we just pulled the app forward, which beats waiting on the
-- bar's own front_app event; a profile retarget focuses nothing and passes false.
local function pushToBar(focused)
  if not sketchybar then return end
  local task
  task = hs.task.new(sketchybar, function() barTasks[task] = nil end, {
    "--trigger", barEvent,
    "APP=" .. (sw.apps[currentIndex] or ""),
    "INDEX=" .. currentIndex,
    "COUNT=" .. #sw.apps,
    "PROFILE=" .. (core.profile() or ""),
    "MAXIMIZED=" .. tostring(maximized),
    -- Names as macOS reports them, so the bar can match against front_app.
    "APP_NAME=" .. ((workspace[currentIndex] or {}).app or ""),
    "ANCHOR_NAME=" .. (anchorEntry and anchorEntry.app or ""),
    "FOCUSED=" .. tostring(focused and true or false),
  })
  barTasks[task] = true
  -- A task that never launched never calls back, so it would sit here forever.
  if not task:start() then barTasks[task] = nil end
end

-- Assert by name: the bare nil-index error names no profile, and the block is
-- easy to forget when copying an existing one.
local function switcherFor(name, profile)
  assert(profile.switcher, "tessera: profile '" .. name .. "' has no switcher block")
  return profile.switcher
end

-- Which app the profile starts on, without disturbing the order the number keys
-- follow. `start` names one of `apps`; unset means the first.
local function startIndex(name, s)
  if not s.start then return 1 end
  for i, ref in ipairs(s.apps) do
    if ref == s.start then return i end
  end
  error("tessera: profile '" .. name .. "' starts on '" .. s.start ..
        "', which is not in its switcher apps")
end

-- Retargets state only -- window-layout places the windows. Except at load,
-- where nothing else has run yet.
local function useProfile(name, apply)
  -- Resolve everything that can throw (unknown app, bad `start`) before any of
  -- it lands, so a bad profile leaves the live one intact instead of half-swapped.
  local block = switcherFor(name, config.profile(name))
  local anchor = config.app(block.anchor)
  local apps = {}
  for _, ref in ipairs(block.apps) do
    apps[#apps + 1] = config.app(ref)
  end
  local index = startIndex(name, block)

  sw, anchorEntry, workspace, currentIndex = block, anchor, apps, index
  maximized = false
  local first = workspace[currentIndex]
  -- A profile may list no cycled apps; just pin the anchor.
  if apply then
    placeAnchor(first == nil)
    if first then placeApp(first, sw.otherSlot, true, true) end
  end
  pushToBar(apply and first ~= nil)
end

local function switchWorkspace(index)
  local count = #workspace
  if count == 0 then return end
  if index < 1 then index = count end
  if index > count then index = 1 end
  currentIndex = index
  maximized = false
  -- Anchor first and focus-free, so the switched-to app ends up focused.
  placeAnchor(false)
  placeApp(workspace[currentIndex], sw.otherSlot, true, true)
  pushToBar(true)
end

local function toggleMaximize()
  local entry = workspace[currentIndex]
  if not entry then return end
  if maximized then
    maximized = false
    placeAnchor(false)                          -- re-pin the anchor beside it
    placeApp(entry, sw.otherSlot, true, true)
  else
    maximized = true
    placeApp(entry, sw.fullSlot, true, true)    -- fill the screen, cover anchor
  end
  pushToBar(true)
end

-- Widest apps list across all profiles: bind that many number keys once and no
-- profile switch ever has to rebind.
local function maxApps()
  local n = 0
  for name, p in pairs(config.profiles) do
    local count = #switcherFor(name, p).apps
    if count > n then n = count end
  end
  return n
end

-- modifier+1..N. A key past the active profile's count is a no-op, not a wrap.
for i = 1, maxApps() do
  hs.hotkey.bind(keys.modifier, tostring(i), function()
    if i <= #workspace then switchWorkspace(i) end
  end)
end

hs.hotkey.bind(keys.modifier, "left", function() switchWorkspace(currentIndex - 1) end)
hs.hotkey.bind(keys.modifier, "right", function() switchWorkspace(currentIndex + 1) end)
hs.hotkey.bind(keys.modifier, keys.maximizeKey, toggleMaximize)

-- Watcher events carry a name; an entry may hold a bundle id instead.
local function isAnchor(name, app)
  if name == anchorEntry.app then return true end
  if app and app:bundleID() == anchorEntry.app then return true end
  return false
end

-- Re-pin the anchor whenever it relaunches, in case it opens elsewhere.
M.anchorWatcher = hs.application.watcher.new(function(name, eventType, app)
  if eventType == hs.application.watcher.launched and isAnchor(name, app) then
    -- Position only; don't yank focus from whatever you're using.
    hs.timer.doAfter(0.5, function() placeAnchor(false) end)
  end
end)
M.anchorWatcher:start()

-- Exposed so the bar can ask for the current state when IT restarts, rather
-- than sitting blank until the next switch.
M.pushToBar = function() pushToBar() end

-- Record the starting profile before subscribing, so pressing its own hotkey
-- later is a no-op broadcast rather than a pointless retarget.
core.setProfile(config.defaultProfile)
core.onProfile(function(name) useProfile(name, false) end)

useProfile(config.defaultProfile, true)

return M
