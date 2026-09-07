-- layout-workspace.lua
--
-- Pins one "anchor" app to a fixed slot, and lets you switch which app occupies
-- another slot via keyboard shortcuts -- a mini workspace switcher for one
-- region of your screen. Which apps and slots depends on the active profile;
-- all configuration lives in tessera-config.lua.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

local M = {}

-- Tuning: how long to keep retrying to grab a freshly launched app's window,
-- how often to poll, and how long to wait for a spawned window before falling
-- back to the existing one.
local launchTimeout = 5.0
local pollInterval = 0.2
local newWindowTimeout = 1.5

local keys = config.switcher -- the hotkey layer; targets come from the profile

-- Retargeted by useProfile() whenever the active profile changes.
local sw          -- the active profile's switcher block
local anchorEntry
local workspace = {}
local currentIndex = 1

-- One in-flight launch poller per entry key, so rapid re-switches don't stack
-- parallel timers all racing to place the same window.
local pending = {}

local function entryKey(entry)
  return core.entryKey(entry.app, entry.titleSuffix)
end

local function place(win, slotName)
  core.setFrameClamped(win, config.slot(slotName))
end

-- Record the window we placed in the shared registry, so a repeat press can
-- reuse it and window-layout.lua can reposition the exact same window.
local function track(key, win)
  core.publishWindow(key, win)
end

-- Set of current standard-window ids for an app, so we can spot a new one.
local function windowIds(appName)
  local ids = {}
  for _, w in ipairs(core.appWindows(appName)) do
    ids[w:id()] = true
  end
  return ids
end

-- The first standard window whose id isn't in `before` -- i.e. one that
-- appeared after we asked the app to open a new window.
local function freshWindow(appName, before)
  for _, w in ipairs(core.appWindows(appName)) do
    if not before[w:id()] then return w end
  end
  return nil
end

-- The app's standard window whose title ends with `suffix`, or nil. Used to
-- target a specific window like Helium "Development".
local function titledWindow(appName, suffix)
  for _, w in ipairs(core.appWindows(appName)) do
    if core.endsWith(w:title() or "", suffix) then return w end
  end
  return nil
end

-- A window for an UNTITLED entry: any of the app's windows except ones a titled
-- sibling has claimed, so an untitled entry never steals a titled one's window.
-- Prefers each process's MAIN window: for an app with several windows open,
-- that's the one you last used, whereas appWindows order is only incidentally
-- z-order within a process and undefined across two of them.
local function plainWindow(appName)
  local reserved = config.reservedSuffixes(appName)
  -- isStandard matches what appWindows returns, so the main-window shortcut
  -- can't place a dialog or panel the scan would have skipped.
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

-- Open a titled entry that isn't running yet. `launch` (raw command) wins, then
-- profileDir (open the right profile in a new window), else plain launch.
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

-- Ask an already-running app to open a new window. Prefer a real menu item
-- (reliable, no focus games); fall back to Cmd+N routed to the app.
local function openNewWindow(app)
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

-- Positions an entry's window into `slotName`, launching the app if needed.
-- Retries until a window exists or the timeout hits.
--   * titleSuffix set -> always reuse the SPECIFIC window whose title matches,
--     never spawn a new one.
--   * otherwise, spawnNew controls whether an already-open app gets a fresh
--     window (workspace switch) or just has its existing one moved (anchor).
local function placeApp(entry, slotName, spawnNew, focus)
  local shouldFocus = focus ~= false
  local appName = entry.app
  local key = entryKey(entry)

  -- Cancel any poller already chasing this entry; newest call wins.
  if pending[key] then
    pending[key]:stop()
    pending[key] = nil
  end

  -- Title-matched entry: reuse the one specific window, launch if missing.
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

  -- Already running with a window we're allowed to claim.
  local plain = plainWindow(appName)
  if plain then
    if not spawnNew then
      place(plain, slotName)
      if shouldFocus then plain:focus() end
      return
    end

    -- Reuse the window we placed before, if it's still around.
    local reuse = core.window(key)
    if reuse then
      place(reuse, slotName)
      if shouldFocus then reuse:focus() end
      return
    end

    -- Otherwise spawn a fresh window here rather than yanking an existing one.
    local before = windowIds(appName)
    openNewWindow(plain:application())

    local elapsed = 0
    pending[key] = hs.timer.doUntil(
      function() return elapsed >= launchTimeout end,
      function(timer)
        elapsed = elapsed + pollInterval
        local w = freshWindow(appName, before)
        -- No new window in time? Fall back to the existing one.
        if not w and elapsed >= newWindowTimeout then w = plainWindow(appName) end
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

  -- Not running (or no window yet): launch and grab its first window.
  if #core.apps(appName) == 0 then
    hs.application.open(appName, 0, true)
  end

  local elapsed = 0
  pending[key] = hs.timer.doUntil(
    function() return elapsed >= launchTimeout end,
    function(timer)
      elapsed = elapsed + pollInterval
      local win = plainWindow(appName)
      if win then
        place(win, slotName)
        if shouldFocus then win:focus() end
        if spawnNew then track(key, win) end
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

-- Whether the current workspace app is blown up to the full slot (covering the
-- anchor). Reset whenever we switch, since a switch restores the split.
local maximized = false

-- Every profile must carry a switcher block -- without one the hotkeys have
-- nothing to target. Assert by name: the bare nil-index error names no profile,
-- and a block is easy to forget when copying an existing profile.
local function switcherFor(name, profile)
  assert(profile.switcher, "tessera: profile '" .. name .. "' has no switcher block")
  return profile.switcher
end

-- Point the switcher at a profile's `switcher` block. Only retargets state --
-- placing the windows is the profile's own job (window-layout walks `place`),
-- except at load, where nothing else has run yet.
local function useProfile(name, apply)
  sw = switcherFor(name, config.profile(name))
  anchorEntry = config.app(sw.anchor)
  workspace = {}
  for _, ref in ipairs(sw.apps) do
    workspace[#workspace + 1] = config.app(ref)
  end
  currentIndex = 1
  maximized = false
  -- A profile may legitimately list no cycled apps -- just pin the anchor.
  if apply then
    placeAnchor(workspace[1] == nil)
    if workspace[1] then placeApp(workspace[1], sw.otherSlot, true, true) end
  end
end

local function switchWorkspace(index)
  local count = #workspace
  if count == 0 then return end
  if index < 1 then index = count end
  if index > count then index = 1 end
  currentIndex = index
  maximized = false
  -- Re-assert the anchor first (focus-free), so the switched-to app is
  -- activated last and keeps keyboard focus.
  placeAnchor(false)
  placeApp(workspace[currentIndex], sw.otherSlot, true, true)
end

-- Toggle the current workspace app between its slot and the full screen.
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
end

-- Widest `apps` list across all profiles -- how many number keys to claim, so
-- the bindings cover whichever profile is active without ever rebinding.
local function maxApps()
  local n = 0
  for name, p in pairs(config.profiles) do
    local count = #switcherFor(name, p).apps
    if count > n then n = count end
  end
  return n
end

-- Direct-jump hotkeys: modifier+1, +2, +3 ... A key past the active profile's
-- app count is a no-op rather than a wrap-around.
for i = 1, maxApps() do
  hs.hotkey.bind(keys.modifier, tostring(i), function()
    if i <= #workspace then switchWorkspace(i) end
  end)
end

-- Cycle hotkeys: modifier+Left (previous) and +Right (next).
hs.hotkey.bind(keys.modifier, "left", function() switchWorkspace(currentIndex - 1) end)
hs.hotkey.bind(keys.modifier, "right", function() switchWorkspace(currentIndex + 1) end)

-- Maximize toggle: modifier+F fills the screen with the current workspace app.
hs.hotkey.bind(keys.modifier, keys.maximizeKey, toggleMaximize)

-- Match a watcher event to the anchor app by name OR bundle id.
local function isAnchor(name, app)
  if name == anchorEntry.app then return true end
  if app and app:bundleID() == anchorEntry.app then return true end
  return false
end

-- Re-pin the anchor any time it's (re)launched, in case it opens elsewhere.
M.anchorWatcher = hs.application.watcher.new(function(name, eventType, app)
  if eventType == hs.application.watcher.launched and isAnchor(name, app) then
    -- Re-pin position only; don't yank focus from whatever you're using.
    hs.timer.doAfter(0.5, function() placeAnchor(false) end)
  end
end)
M.anchorWatcher:start()

-- Record the starting profile before subscribing, so pressing its own hotkey
-- later is a no-op broadcast rather than a pointless retarget.
core.setProfile(config.defaultProfile)
core.onProfile(function(name) useProfile(name, false) end)

-- Set the initial layout when this file loads.
useProfile(config.defaultProfile, true)

return M
