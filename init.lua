-- tessera/init.lua
--
-- Package entry point. From ~/.hammerspoon/init.lua just `require("tessera")`;
-- this wires up the tools and owns their load order. Returns the config table
-- so callers can inspect/tweak it programmatically if they want.

require("tessera.layout-workspace") -- half-screen app switcher
require("tessera.window-layout")    -- full-desktop layout profiles

return require("tessera.config")
