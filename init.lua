-- tessera/init.lua
--
-- Package entry point. From ~/.hammerspoon/init.lua just `require("tessera")`;
-- this owns the load order and returns the config table.

-- Outside the repo wins, since it survives re-cloning. Resolved here rather
-- than in the feature modules so a missing or broken config says so plainly,
-- and so both modules get the same table whichever file it came from.
local candidates = {
  "tessera-config", -- ~/.hammerspoon/tessera-config.lua
  "tessera.config", -- ~/.hammerspoon/tessera/config.lua, gitignored
}

local found = {}
for _, name in ipairs(candidates) do
  if package.searchpath(name, package.path) then found[#found + 1] = name end
end

if #found == 0 then
  error(
    "tessera: no config found. Create one from the template:\n" ..
    "  cp ~/.hammerspoon/tessera/tessera-config.example.lua ~/.hammerspoon/tessera-config.lua\n" ..
    "  (or ~/.hammerspoon/tessera/config.lua to keep it inside the repo)",
    0
  )
end
if #found > 1 then
  print(("tessera: %d configs present (%s) -- using %s")
    :format(#found, table.concat(found, ", "), found[1]))
end

local ok, config = pcall(require, found[1])
if not ok then
  error("tessera: " .. found[1] .. " failed to load:\n  " .. tostring(config), 0)
end

local schema = require("tessera.schema")
local core = require("tessera.layout-shared")
schema.attach(config)

-- Alias, so the modules' `require("tessera-config")` resolves to the file we
-- picked even when it was the in-repo one.
package.loaded["tessera-config"] = config

-- The last profile used with these screens, if it still suits them.
config.startProfile = config.bestProfile(hs.settings.get(core.profileKey()))

local workspace = require("tessera.layout-workspace") -- half-screen app switcher
require("tessera.window-layout")    -- full-desktop layout profiles
if schema.enabled(config, "slotMove") then
  require("tessera.slot-move")      -- focused window -> a slot of the active profile
end
if schema.enabled(config, "overlay") then
  require("tessera.overlay")        -- hold a key layer to see what it does
end

-- Accessibility can vanish across a reboot; without it the keys just look dead.
local axWarned = false
local function checkAccessibility()
  local ok = hs.accessibilityState()
  if not ok and not axWarned then
    hs.alert.show("tessera: Hammerspoon has no Accessibility permission", 5)
    print("tessera: accessibility is off; nothing will place until it's re-enabled")
  end
  axWarned = not ok
end
checkAccessibility()
config.axTimer = hs.timer.doEvery(60, checkAccessibility)

-- Entry points for `hs -c`; the Sketchybar item calls cycle on scroll.
config.status = workspace.status

-- A trackpad scroll arrives as a burst of events; one step per 0.4s.
local lastScroll = 0
config.cycle = function(step)
  local now = hs.timer.secondsSinceEpoch()
  if now - lastScroll < 0.4 then return end
  lastScroll = now
  workspace.cycle(step)
end

print("tessera: started, profile " .. config.startProfile)

return config
