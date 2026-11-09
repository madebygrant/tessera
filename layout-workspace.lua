-- layout-workspace.lua
--
-- The half-screen switcher: pins an anchor app to one slot and cycles other
-- apps through a second one. Which apps and slots come from the active profile.

local core = require("tessera.layout-shared")
local config = require("tessera-config")
local schema = require("tessera.schema")

local M = {}

-- How long to keep chasing a launching app's window, and how often to look.
local launchTimeout = 5.0
local pollInterval = 0.2

local keys = config.keys -- the hotkey layer; targets come from the profile

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
  -- One AX pass per process: mains win, else the first claimable window seen.
  local fallback
  for _, a in ipairs(core.apps(appName)) do
    local main = a:mainWindow()
    if claimable(main) then return main end
    if not fallback then
      for _, w in ipairs(a:allWindows()) do
        if claimable(w) then fallback = w break end
      end
    end
  end
  return fallback
end

-- hs.application.open on a running app with no windows sends it a reopen,
-- which makes most apps open one.
local function launchEntry(entry)
  if not core.spawn(entry) then hs.application.open(entry.app, 0, true) end
end

-- The window an entry already has, if any. Adopting one rather than opening
-- another matters after a reboot, when the registry is empty and an app
-- launched at login already has its window.
--   titleSuffix -> the SPECIFIC window whose title matches.
--   remember    -> try the registry first (cycled apps); the anchor is just
--                  whatever window the app has.
local function existingWindow(entry, remember)
  if entry.titleSuffix then return titledWindow(entry.app, entry.titleSuffix) end
  return (remember and core.window(entryKey(entry))) or plainWindow(entry.app)
end

-- Place an entry's window in `slotName`, launching the app if it has none.
-- Never opens a second window; that's window-layout's job.
--   opts.remember  -> record the window in the registry
--   opts.focus     -> false leaves focus where it is
--   opts.adoptOnly -> place an existing window or do nothing
local function placeApp(entry, slotName, opts)
  local key = entryKey(entry)
  local win = existingWindow(entry, opts.remember)
  -- Checked before cancelling, so a no-op call leaves a launch in flight alone.
  if not win and opts.adoptOnly then return end

  -- Cancel any poller already chasing this entry; newest call wins.
  if pending[key] then
    pending[key]:stop()
    pending[key] = nil
  end

  local function land(w)
    place(w, slotName)
    if opts.focus ~= false then w:focus() end
    if opts.remember or entry.titleSuffix then track(key, w) end
  end

  if win then
    land(win)
    return
  end

  local blocked = core.launchBlocker(entry.app)
  if blocked then
    core.alert(blocked)
    return
  end

  launchEntry(entry)
  local elapsed = 0
  pending[key] = hs.timer.doEvery(pollInterval, function()
    elapsed = elapsed + pollInterval
    local w = existingWindow(entry, false)
    if not w and elapsed < launchTimeout then return end
    pending[key]:stop()
    pending[key] = nil
    if w then
      land(w)
    else
      -- Say so, or the keys just look dead until the window finally shows.
      core.alert("no window from " .. entry.app .. " after " .. launchTimeout .. "s")
    end
  end)
end

local function placeAnchor(focus)
  placeApp(anchorEntry, sw.anchorSlot, { focus = focus })
end

local function cancelPending()
  for key, timer in pairs(pending) do
    timer:stop()
    pending[key] = nil
  end
end

-- Whether the cycled app covers the anchor. A switch restores the split.
local maximized = false

-- Sketchybar readout, opt-in like every other feature block.
local barConfig = config.sketchybar or {}
local barEnabled = schema.enabled(config, "sketchybar")
local barEvent = barConfig.event or "tessera_switcher"

-- Sketchybar's own PATH isn't Hammerspoon's, so find the binary rather than
-- shelling out by name. nil = disabled or absent, and every push is a no-op.
local sketchybar = (function()
  if not barEnabled then return nil end
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

-- Retargets state only; window-layout places the windows. Except at load,
-- where nothing else has run yet: then it places too, without focus, so a
-- reload doesn't yank you out of whatever you were doing. `launchAtLoad =
-- false` in the config keeps load from opening apps that aren't running.
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

  -- A launch still chasing the old profile would land in its slots.
  cancelPending()
  sw, anchorEntry, workspace, currentIndex = block, anchor, apps, index
  maximized = false
  local first = workspace[currentIndex]
  -- A profile may list no cycled apps; just pin the anchor.
  if apply then
    local adoptOnly = config.launchAtLoad == false
    placeApp(anchorEntry, sw.anchorSlot, { focus = false, adoptOnly = adoptOnly })
    if first then
      placeApp(first, sw.otherSlot, { remember = true, focus = false, adoptOnly = adoptOnly })
    end
  end
  pushToBar(false)
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
  placeApp(workspace[currentIndex], sw.otherSlot, { remember = true })
  pushToBar(true)
end

local function toggleMaximize()
  local entry = workspace[currentIndex]
  if not entry then return end
  if maximized then
    maximized = false
    placeAnchor(false)                                   -- re-pin the anchor beside it
    placeApp(entry, sw.otherSlot, { remember = true })
  else
    maximized = true
    placeApp(entry, sw.fullSlot, { remember = true })    -- fill the screen, cover anchor
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
  hs.hotkey.bind(keys.switcher, tostring(i), function()
    if i <= #workspace then switchWorkspace(i) end
  end)
end

hs.hotkey.bind(keys.switcher, "left", function() switchWorkspace(currentIndex - 1) end)
hs.hotkey.bind(keys.switcher, "right", function() switchWorkspace(currentIndex + 1) end)
hs.hotkey.bind(keys.switcher, keys.maximize, toggleMaximize)

-- Watcher events carry a name; an entry may hold a bundle id instead.
local function isAnchor(name, app)
  if not anchorEntry then return false end
  if name == anchorEntry.app then return true end
  if app and app:bundleID() == anchorEntry.app then return true end
  return false
end

local function centreIn(win, frame)
  local f = win:frame()
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  return cx >= frame.x and cx <= frame.x + frame.w
     and cy >= frame.y and cy <= frame.y + frame.h
end

-- macOS raises ALL of an app's windows when it activates, so focusing Helium on
-- the main screen pops its other profile's window over whatever the switcher
-- has in its slot. Put the slot's own window back on top; :raise() leaves focus
-- with the app you activated.
local function restoreSlotTop(app)
  local entry = workspace[currentIndex]
  if not entry or not app:isRunning() then return end
  if app:name() == entry.app or app:bundleID() == entry.app then return end

  local slot = config.slot(maximized and sw.fullSlot or sw.otherSlot)
  -- CoreGraphics first: it needs no Accessibility call into the activated app,
  -- which on a hung app blocks Hammerspoon until the AX timeout.
  if not core.hasWindowIn(app:pid(), slot) then return end
  local tracked = core.window(entryKey(entry))
  if not tracked or not centreIn(tracked, slot) then return end

  -- Only intrude if a window the user did NOT activate landed in the slot. If
  -- the one they activated is in the slot (every app shares it in a laptop
  -- profile), they chose it: leave it on top.
  local focused = app:focusedWindow()
  if focused and centreIn(focused, slot) then return end
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and (not focused or w:id() ~= focused:id()) and centreIn(w, slot) then
      tracked:raise()
      return
    end
  end
end

M.appWatcher = hs.application.watcher.new(function(name, eventType, app)
  -- Re-pin the anchor whenever it relaunches, in case it opens elsewhere.
  if eventType == hs.application.watcher.launched and isAnchor(name, app) then
    -- Position only: no focus, and no launch. Any process of the anchor's app
    -- lands here, including the ones a launch spawns, so launching would loop.
    hs.timer.doAfter(0.5, function()
      placeApp(anchorEntry, sw.anchorSlot, { focus = false, adoptOnly = true })
    end)
  elseif eventType == hs.application.watcher.activated and app then
    -- Synchronously: a deferred raise leaves the stray window visible for the
    -- length of the delay, which reads as a flash.
    restoreSlotTop(app)
  end
end)
M.appWatcher:start()

-- Exposed so the bar can ask for the current state when IT restarts, rather
-- than sitting blank until the next switch.
M.pushToBar = function() pushToBar() end

-- Read by the overlay; copies, so they can't mutate live state.
M.state = function()
  local apps = {}
  for i, ref in ipairs(sw and sw.apps or {}) do apps[i] = ref end
  return {
    profile = core.profile(),
    anchor = sw and sw.anchor,
    anchorSlot = sw and sw.anchorSlot,
    otherSlot = sw and sw.otherSlot,
    apps = apps,
    index = currentIndex,
    maximized = maximized,
  }
end

M.cycle = function(step) switchWorkspace(currentIndex + step) end

-- For `hs -c 'print(require("tessera").status())'` when the keys go quiet.
M.status = function()
  local lines = {
    "profile:   " .. tostring(core.profile()),
    "index:     " .. currentIndex .. "/" .. #workspace
      .. (maximized and " (maximized)" or ""),
    "anchor:    " .. (anchorEntry and anchorEntry.app or "none"),
    "ax:        " .. tostring(hs.accessibilityState()),
    "pending:   " .. (next(pending) and table.concat(
      (function() local t = {} for k in pairs(pending) do t[#t + 1] = (k:gsub("%z", "/")) end return t end)(), ", ")
      or "none"),
  }
  for i, entry in ipairs(workspace) do
    local w = core.window(entryKey(entry))
    lines[#lines + 1] = ("  %d. %-12s %s"):format(i, entry.app,
      w and ("#" .. w:id() .. " " .. tostring(w:title())) or "(no window tracked)")
  end
  return table.concat(lines, "\n")
end

-- Record the starting profile before subscribing, so pressing its own hotkey
-- later is a no-op broadcast rather than a pointless retarget.
core.setProfile(config.startProfile)
core.onProfile(function(name) useProfile(name, false) end)

-- window-layout stacks every cycled app in the same slot without raising any,
-- so put the one the index points at on top. A re-press keeps the index.
core.onApplied(function()
  maximized = false
  local entry = workspace[currentIndex]
  local win = entry and existingWindow(entry, true)
  if win then win:raise() end
  pushToBar(false)
end)

useProfile(config.startProfile, true)

return M
