-- overlay.lua
--
-- Hold a key layer (keys.switcher or keys.slotMove) on its own for a moment and
-- the active profile's slots are drawn on screen with what each key does.
-- Releasing the modifiers hides it; pressing a key makes it a chord instead.

local core = require("tessera.layout-shared")
local config = require("tessera-config")
local schema = require("tessera.schema")
local workspace = require("tessera.layout-workspace")
local slotMove = schema.enabled(config, "slotMove") and require("tessera.slot-move") or nil

local M = {}

local delay = config.overlay.delay or 1.0

local ACCENT = { red = 0.38, green = 0.78, blue = 1.0, alpha = 1 }
local DIM = { white = 1, alpha = 0.7 }
local WHITE = { white = 1, alpha = 1 }
local FILL = { white = 0.05, alpha = 0.55 }

local modSet, sameMods, glyphs, keyLabel =
  core.modSet, core.sameMods, core.modGlyphs, core.keyLabel

local switcherMods = modSet(config.keys.switcher)
local slotMoveMods = slotMove and modSet(config.keys.slotMove) or nil

-- convertFont to bold yields .SFNS-Bold, which macOS 27 rejects by name.
local SYSTEM = hs.styledtext.defaultFonts.system.name
local BOLD = hs.styledtext.defaultFonts.boldSystem.name
local function font(size, bold)
  return { name = bold and BOLD or SYSTEM, size = size }
end

local function text(str, size, color, bold, align)
  return hs.styledtext.new(str, {
    font = font(size, bold),
    color = color or WHITE,
    paragraphStyle = { alignment = align or "center", lineSpacing = 4 },
  })
end

-- Sizes are tuned for a laptop-height slot; a tall 4K slot gets up to 1.8x.
local function scaleFor(frame)
  return math.max(1, math.min(1.8, frame.h / 900))
end

local canvases = {}

local function clear()
  for _, c in ipairs(canvases) do c:delete() end
  canvases = {}
end

-- One translucent rounded box over `frame` with `body` centred in it.
local function box(frame, body, highlight)
  local size = hs.drawing.getTextDrawingSize(body)
  local textW = math.min(size.w + 4, frame.w)
  local c = hs.canvas.new(frame)
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior({ "canJoinAllSpaces", "stationary" })
  c:appendElements(
    {
      type = "rectangle", action = "strokeAndFill",
      fillColor = FILL,
      strokeColor = highlight and ACCENT or DIM,
      strokeWidth = highlight and 4 or 2,
      roundedRectRadii = { xRadius = 14, yRadius = 14 },
      frame = { x = 8, y = 8, w = frame.w - 16, h = frame.h - 16 },
    },
    {
      type = "text", text = body,
      -- Sized to the text and centred, so left-aligned lines stay a centred block.
      frame = { x = (frame.w - textW) / 2, y = (frame.h - size.h) / 2, w = textW, h = size.h + 4 },
    }
  )
  c:show()
  canvases[#canvases + 1] = c
end

-- A pill along the bottom of `screenFrame`.
local function legend(screenFrame, body)
  local size = hs.drawing.getTextDrawingSize(body)
  local w, h = size.w + 48, size.h + 24
  box({
    x = screenFrame.x + (screenFrame.w - w) / 2,
    y = screenFrame.y + screenFrame.h - h - 40,
    w = w, h = h,
  }, body, false)
end

local function profileLegend(active, k)
  local names = {}
  for name in pairs(config.profiles) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    return config.profiles[a].key:lower() < config.profiles[b].key:lower()
  end)
  local body = text("", 15 * k)
  for i, name in ipairs(names) do
    local p = config.profiles[name]
    local chord = glyphs(modSet(p.modifier or config.keys.profile)) .. keyLabel(p.key)
    local on = name == active
    if i > 1 then body = body .. text("     ", 15 * k) end
    body = body .. text(chord .. "  ", 15 * k, DIM)
      .. text(core.prettyName(name), 15 * k, on and ACCENT or WHITE, on)
  end
  return body
end

local function drawSwitcher()
  local st = workspace.state()
  if not st.profile then return end
  local mods = glyphs(switcherMods)

  local anchorFrame = config.slot(st.anchorSlot)
  local k = scaleFor(anchorFrame)
  local otherFrame = config.slot(st.otherSlot)
  -- A full-screen profile shares one frame; the list box alone says it all.
  local shared = anchorFrame.x == otherFrame.x and anchorFrame.y == otherFrame.y
    and anchorFrame.w == otherFrame.w and anchorFrame.h == otherFrame.h
  if not shared then
    box(anchorFrame,
      text(core.prettyName(st.anchor) .. "\n", 30 * k, WHITE, true)
        .. text("anchor", 15 * k, DIM), false)
  end

  k = scaleFor(otherFrame)
  local body = text("", 22 * k, WHITE, false, "left")
  for i, ref in ipairs(st.apps) do
    local on = i == st.index
    body = body .. text(mods .. i .. "    ", 22 * k, DIM, false, "left")
      .. text(core.prettyName(ref) .. "\n", 22 * k, on and ACCENT or WHITE, on, "left")
  end
  local hints = mods .. "← →  cycle      " .. mods .. keyLabel(config.keys.maximize)
    .. (st.maximized and "  restore" or "  maximize")
  body = body .. text("\n" .. hints, 14 * k, DIM, false, "left")
  box(otherFrame, body, true)

  local slot = config.slots[st.anchorSlot]
  local screen = core.resolveScreen(config.screens[slot.screen] or slot.screen)
  local sf = screen:frame()
  legend(sf, profileLegend(st.profile, scaleFor(sf)))
end

local function drawSlotMove()
  local mods = glyphs(slotMoveMods)
  for i, name in ipairs(slotMove.slots()) do
    local frame = config.slot(name)
    local k = scaleFor(frame)
    box(frame,
      text(mods .. i .. "\n", 34 * k, WHITE, true)
        .. text(core.prettyName(name) .. "\n", 16 * k, DIM)
        .. text("send the focused window here", 13 * k, DIM), false)
  end
end

local function draw(layer)
  clear()
  if layer == "switcher" then drawSwitcher() else drawSlotMove() end
end

-- hs -c 'require("tessera.overlay").show("switcher")' draws it without holding keys.
M.show = draw
M.hide = clear
M.visible = function() return #canvases > 0 end

local held      -- "switcher", "slotMove" or nil
local showTimer

local function layerFor(flags)
  if sameMods(flags, switcherMods) then return "switcher" end
  if slotMoveMods and sameMods(flags, slotMoveMods) then return "slotMove" end
  return nil
end

local types = hs.eventtap.event.types
M.tap = hs.eventtap.new({ types.flagsChanged, types.keyDown }, function(e)
  if e:getType() == types.flagsChanged then
    local layer = layerFor(e:getFlags())
    if layer ~= held then
      held = layer
      if showTimer then showTimer:stop() showTimer = nil end
      clear()
      if layer then
        showTimer = hs.timer.doAfter(delay, function()
          showTimer = nil
          draw(layer)
        end)
      end
    end
  else
    -- A chord, not a look: don't pop up mid-switch.
    if showTimer then showTimer:stop() showTimer = nil end
    -- Already showing: redraw once the hotkey has run, so it shows the new index.
    if #canvases > 0 and held then
      local layer = held
      hs.timer.doAfter(0.15, function()
        if held == layer then draw(layer) end
      end)
    end
  end
  return false
end)
M.tap:start()

-- macOS disables an event tap it judges slow, silently. Turn it back on.
M.watchdog = hs.timer.doEvery(5, function()
  if not M.tap:isEnabled() then M.tap:start() end
end)

return M
