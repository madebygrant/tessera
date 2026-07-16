-- layout-workspace.lua
--
-- Pins one "anchor" app to a fixed slot, and lets you switch which app occupies
-- another slot via keyboard shortcuts -- a mini workspace switcher for one
-- region of your screen. All configuration lives in config.lua.

local core = require("tessera.layout-shared")
local config = require("tessera.config")

local M = {}

-- Tuning: how long to keep retrying to grab a freshly launched app's window,
-- how often to poll, and how long to wait for a spawned window before falling
-- back to the existing one.
local launchTimeout = 5.0
local pollInterval = 0.2
local newWindowTimeout = 1.5

local sw = config.switcher
local anchorEntry = config.app(sw.anchor)

-- Normalize the cycled workspace apps to their config entries.
local workspace = {}
for _, ref in ipairs(sw.apps) do
  workspace[#workspace + 1] = config.app(ref)
end

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
local function windowIds(app)
  local ids = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then ids[w:id()] = true end
  end
  return ids
end

-- The first standard window whose id isn't in `before` -- i.e. one that
-- appeared after we asked the app to open a new window.
local function freshWindow(app, before)
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and not before[w:id()] then return w end
  end
  return nil
end

-- The app's standard window whose title ends with `suffix`, or nil. Used to
-- target a specific window like Helium "Development".
local function titledWindow(app, suffix)
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and core.endsWith(w:title() or "", suffix) then
      return w
    end
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
  local app = hs.application.get(appName)

  -- Cancel any poller already chasing this entry; newest call wins.
  if pending[key] then
    pending[key]:stop()
    pending[key] = nil
  end

  -- Title-matched entry: reuse the one specific window, launch if missing.
  if entry.titleSuffix then
    if app then
      local w = titledWindow(app, entry.titleSuffix)
      if w then
        place(w, slotName)
        if shouldFocus then w:focus() end
        track(key, w)
        return
      end
    end
    launchEntry(entry)
    local elapsed = 0
    pending[key] = hs.timer.doUntil(
      function() return elapsed >= launchTimeout end,
      function(timer)
        elapsed = elapsed + pollInterval
        local a = hs.application.get(appName)
        local w = a and titledWindow(a, entry.titleSuffix)
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

  -- Already running with a window.
  if app and app:mainWindow() then
    if not spawnNew then
      local win = app:mainWindow()
      place(win, slotName)
      if shouldFocus then win:focus() end
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
    local before = windowIds(app)
    openNewWindow(app)

    local elapsed = 0
    pending[key] = hs.timer.doUntil(
      function() return elapsed >= launchTimeout end,
      function(timer)
        elapsed = elapsed + pollInterval
        local a = hs.application.get(appName)
        if not a then return end
        local w = freshWindow(a, before)
        -- No new window in time? Fall back to the existing one.
        if not w and elapsed >= newWindowTimeout then w = a:mainWindow() end
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
  if not app then
    hs.application.open(appName, 0, true)
  end

  local elapsed = 0
  pending[key] = hs.timer.doUntil(
    function() return elapsed >= launchTimeout end,
    function(timer)
      elapsed = elapsed + pollInterval
      local a = hs.application.get(appName)
      local win = a and a:mainWindow()
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

local function switchWorkspace(index)
  local count = #workspace
  if index < 1 then index = count end
  if index > count then index = 1 end
  currentIndex = index
  -- Re-assert the anchor first (focus-free), so the switched-to app is
  -- activated last and keeps keyboard focus.
  placeAnchor(false)
  placeApp(workspace[currentIndex], sw.otherSlot, true, true)
end

-- Direct-jump hotkeys: modifier+1, +2, +3 ...
for i, _ in ipairs(workspace) do
  hs.hotkey.bind(sw.modifier, tostring(i), function()
    switchWorkspace(i)
  end)
end

-- Cycle hotkeys: modifier+Left (previous) and +Right (next).
hs.hotkey.bind(sw.modifier, "left", function() switchWorkspace(currentIndex - 1) end)
hs.hotkey.bind(sw.modifier, "right", function() switchWorkspace(currentIndex + 1) end)

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

-- Set the initial layout when this file loads.
placeAnchor()
switchWorkspace(currentIndex)

return M
