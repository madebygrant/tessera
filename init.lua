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

-- Alias, so the modules' `require("tessera-config")` resolves to the file we
-- picked even when it was the in-repo one.
package.loaded["tessera-config"] = config

require("tessera.layout-workspace") -- half-screen app switcher
require("tessera.window-layout")    -- full-desktop layout profiles

return config
