-- tessera/init.lua
--
-- Package entry point. From ~/.hammerspoon/init.lua just `require("tessera")`;
-- this wires up the tools and owns their load order. Returns the config table
-- so callers can inspect/tweak it programmatically if they want.

-- Where the config may live, in priority order:
--   tessera-config  -> ~/.hammerspoon/tessera-config.lua  (outside this repo)
--   tessera.config  -> ~/.hammerspoon/tessera/config.lua  (inside it, gitignored)
-- Outside wins: it survives re-cloning the repo. Loaded here rather than in the
-- feature modules so a missing or broken config reports itself plainly, and so
-- both modules get the same table whichever file it came from.
local candidates = { "tessera-config", "tessera.config" }

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

local config = require(found[1])

-- Alias, so the feature modules' `require("tessera-config")` resolves to the
-- config we picked even when it was the in-repo one.
package.loaded["tessera-config"] = config

require("tessera.layout-workspace") -- half-screen app switcher
require("tessera.window-layout")    -- full-desktop layout profiles

return config
