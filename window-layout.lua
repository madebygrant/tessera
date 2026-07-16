-- window-layout.lua
--
-- Applies a named full-desktop layout profile (config.profiles) on a hotkey:
-- each app is placed into its slot, launching/matching by the app's config.
-- Reuses the switcher's tracked window when a profile entry asks for it.

local core = require("tessera.layout-shared")
local config = require("tessera.config")

-- The switcher's tracked window for an app entry (via the shared registry), or
-- nil if it hasn't been placed this session. Skips windows already reserved.
local function switcherWindow(entry, used)
  local w = core.window(core.entryKey(entry.app, entry.titleSuffix))
  if w and not used[w:id()] then return w end
  return nil
end

-- First matching, still-unused window of an app (by title suffix if given).
local function findWindow(app, suffix, used)
  if not app then return nil end
  for _, win in ipairs(app:allWindows()) do
    local id = win:id()
    if id and not used[id] then
      local title = win:title() or ""
      if not suffix or core.endsWith(title, suffix) then
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

  local app = hs.application.get(entry.app)
  local win = findWindow(app, entry.titleSuffix, used)
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

-- Per-profile debounce, so a double hotkey press doesn't fight itself.
local lastRun = {}

local function applyProfile(name, profile)
  local now = hs.timer.secondsSinceEpoch()
  if lastRun[name] and now - lastRun[name] < 10 then return end
  lastRun[name] = now
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
