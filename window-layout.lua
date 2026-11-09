-- window-layout.lua
--
-- Applies a named profile (config.profiles) on its hotkey: each app into its
-- slot, reusing the switcher's tracked window when an entry asks for it.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

-- Watcher and timer handles live here so they outlast the chunk.
local M = {}

-- The switcher's tracked window for an entry, unless this pass already used it.
local function switcherWindow(entry, used)
  local w = core.window(core.entryKey(entry.app, entry.titleSuffix))
  if w and not used[w:id()] then return w end
  return nil
end

-- First unused window of an app, across its processes. Without a suffix, skip
-- windows a titled sibling entry claims.
local function findWindow(appName, suffix, used)
  local reserved = not suffix and config.reservedSuffixes(appName) or nil
  for _, win in ipairs(core.appWindows(appName)) do
    local id = win:id()
    if id and not used[id] then
      local title = win:title() or ""
      if suffix then
        if core.endsWith(title, suffix) then return win end
      elseif not core.endsWithAny(title, reserved) then
        return win
      end
    end
  end
  return nil
end

local function launchEntry(entry)
  if core.spawn(entry) then return end
  -- Running but every window taken (same app in two slots): launchOrFocus would
  -- just focus one of those, so ask for a new one.
  local running = core.primaryApp(entry.app)
  if running then
    core.openNewWindow(running)
  else
    hs.application.launchOrFocus(entry.app)
  end
end

-- A retry from a superseded apply stops, so hopping between profiles can't
-- drop a late window into the previous layout.
local generation = 0
local current = nil -- { gen, name, outstanding, launch }

local function settle(apply)
  apply.outstanding = apply.outstanding - 1
  if apply.outstanding == 0 and apply == current then core.applied(apply.name) end
end

-- Place one profile entry, retrying while the app/window appears.
local function placeEntry(item, used, apply, attempt)
  attempt = attempt or 1
  if apply ~= current then return settle(apply) end
  local entry = config.app(item.app)
  local frame = config.slot(item.slot)

  -- With nothing tracked yet (cold boot, switcher untouched) fall through and
  -- place it like any other entry: findWindow adopts before launching, so it
  -- still won't open a duplicate.
  local win = item.useSwitcherWindow and switcherWindow(entry, used)
    or findWindow(entry.app, entry.titleSuffix, used)
  if win then
    core.setFrameClamped(win, frame)
    used[win:id()] = true
    return settle(apply)
  end
  if attempt == 1 then
    -- A screen-change re-apply only moves what exists.
    if not apply.launch then return settle(apply) end
    local blocked = core.launchBlocker(entry.app)
    if blocked then
      core.alert(blocked)
      return settle(apply)
    end
    launchEntry(entry)
  end
  if attempt >= 10 then
    core.alert("no window from " .. entry.app .. " after 5s")
    return settle(apply)
  end
  hs.timer.doAfter(0.5, function() placeEntry(item, used, apply, attempt + 1) end)
end

-- Absorbs a double-tap without swallowing a genuine bounce between profiles.
local debounce = 2.0
local lastRun = {}

local function applyProfile(name, profile, launch)
  local now = hs.timer.secondsSinceEpoch()
  if lastRun[name] and now - lastRun[name] < debounce then return end
  lastRun[name] = now
  -- Retarget the switcher before placing, so its slots match this layout.
  core.setProfile(name)
  generation = generation + 1
  local place = profile.place or {}
  current = { gen = generation, name = name, outstanding = #place, launch = launch ~= false }
  local apply = current
  local used = {}
  for _, item in ipairs(place) do
    placeEntry(item, used, apply)
  end
  if #place == 0 then core.applied(name) end
end

-- Dock/undock re-places what's open. A monitor change fires several events a
-- few hundred ms apart, hence the delay.
M.screenTimer = hs.timer.delayed.new(1.0, function()
  local name = core.profile()
  if name then
    lastRun[name] = nil
    applyProfile(name, config.profile(name), false)
  end
end)
M.screenWatcher = hs.screen.watcher.new(function() M.screenTimer:start() end)
M.screenWatcher:start()

-- A profile can carry its own `modifier`; otherwise it sits on the shared layer.
for name, profile in pairs(config.profiles) do
  hs.hotkey.bind(profile.modifier or config.keys.profile, profile.key, function()
    applyProfile(name, profile)
  end)
end

return M
