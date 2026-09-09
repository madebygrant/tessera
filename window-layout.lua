-- window-layout.lua
--
-- Applies a named profile (config.profiles) on its hotkey: each app into its
-- slot, reusing the switcher's tracked window when an entry asks for it.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

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
  if entry.launch then
    hs.execute(entry.launch)
    return
  end
  if entry.profileDir then
    hs.execute(string.format(
      '/usr/bin/open -na %q --args --profile-directory=%q --new-window',
      entry.app, entry.profileDir
    ))
    return
  end
  -- Running but every window taken (same app in two slots): launchOrFocus would
  -- just focus one of those, so ask for a new one.
  local running = core.primaryApp(entry.app)
  if running then
    core.openNewWindow(running)
  else
    hs.application.launchOrFocus(entry.app)
  end
end

-- Place one profile entry, retrying while the app/window appears.
local function placeEntry(item, used, attempt)
  attempt = attempt or 1
  local entry = config.app(item.app)
  local frame = config.slot(item.slot)

  -- With nothing tracked yet (cold boot, switcher untouched) fall through and
  -- place it like any other entry: findWindow adopts before launching, so it
  -- still won't open a duplicate.
  if item.useSwitcherWindow then
    local win = switcherWindow(entry, used)
    if win then
      core.setFrameClamped(win, frame)
      used[win:id()] = true
      return
    end
  end

  local win = findWindow(entry.app, entry.titleSuffix, used)
  if win then
    core.setFrameClamped(win, frame)
    used[win:id()] = true
    return
  end
  if attempt == 1 then launchEntry(entry) end
  if attempt < 10 then
    hs.timer.doAfter(0.5, function() placeEntry(item, used, attempt + 1) end)
  end
end

-- Absorbs a double-tap without swallowing a genuine bounce between profiles.
local debounce = 2.0
local lastRun = {}

local function applyProfile(name, profile)
  local now = hs.timer.secondsSinceEpoch()
  if lastRun[name] and now - lastRun[name] < debounce then return end
  lastRun[name] = now
  -- Retarget the switcher before placing, so its slots match this layout.
  core.setProfile(name)
  local used = {}
  for _, item in ipairs(profile.place) do
    placeEntry(item, used)
  end
end

-- A profile can carry its own `modifier`; otherwise it sits on the shared layer.
for name, profile in pairs(config.profiles) do
  hs.hotkey.bind(profile.modifier or config.keys.profile, profile.key, function()
    applyProfile(name, profile)
  end)
end
