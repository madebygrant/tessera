-- window-layout.lua
--
-- Applies a named full-desktop layout profile (config.profiles) on a hotkey:
-- each app is placed into its slot, launching/matching by the app's config.
-- Reuses the switcher's tracked window when a profile entry asks for it.

local core = require("tessera.layout-shared")
local config = require("tessera-config")

-- The switcher's tracked window for an app entry (via the shared registry), or
-- nil if it hasn't been placed this session. Skips windows already reserved.
local function switcherWindow(entry, used)
  local w = core.window(core.entryKey(entry.app, entry.titleSuffix))
  if w and not used[w:id()] then return w end
  return nil
end

-- First matching, still-unused window of an app, across all its processes (by
-- title suffix if given). Without a suffix, windows a titled sibling entry has
-- claimed are skipped, so an untitled entry can't land on a titled one's window.
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

-- Open an app entry that isn't showing the window we need yet.
local function launchEntry(entry)
  if entry.launch then
    hs.execute(entry.launch)
  elseif entry.profileDir then
    hs.execute(string.format(
      '/usr/bin/open -na %q --args --profile-directory=%q --new-window',
      entry.app, entry.profileDir
    ))
  else
    hs.application.launchOrFocus(entry.app)
  end
end

-- Place one profile entry, retrying a few times while the app/window appears.
local function placeEntry(item, used, attempt)
  attempt = attempt or 1
  local entry = config.app(item.app)
  local frame = config.slot(item.slot)

  -- Reuse the switcher's window when asked; never launch a duplicate for it.
  if item.useSwitcherWindow then
    local win = switcherWindow(entry, used)
    if win then
      core.setFrameClamped(win, frame)
      used[win:id()] = true
    end
    return
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

-- Per-profile debounce, so a double hotkey press doesn't fight itself. Long
-- enough to absorb a double-tap, short enough that bouncing between two
-- profiles to compare them isn't silently ignored.
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

for name, profile in pairs(config.profiles) do
  hs.hotkey.bind(profile.modifier, profile.key, function()
    applyProfile(name, profile)
  end)
end
