-- picker.lua
--
-- A fuzzy chooser over the current profile's apps, maximize, and every layout.
-- Bound to keys.switcher + keys.picker when that's set, and opened by clicking
-- the Sketchybar item.

local core = require("tessera.layout-shared")
local config = require("tessera-config")
local workspace = require("tessera.layout-workspace")
local layout = require("tessera.window-layout")

local M = {}

local function profileSummary(name)
  local p = config.profiles[name]
  local apps = {}
  for _, ref in ipairs(p.switcher.apps) do apps[#apps + 1] = core.prettyName(ref) end
  return core.prettyName(p.switcher.anchor) .. " + " .. table.concat(apps, ", ")
end

local function allChoices()
  local st = workspace.state()
  local out = {}
  for i, ref in ipairs(st.apps) do
    out[#out + 1] = {
      text = core.prettyName(ref),
      subText = (i == st.index and "Showing now · " or "") .. "slot " .. i .. " in "
        .. core.prettyName(st.profile),
      kind = "app", index = i,
    }
  end
  if #st.apps > 0 then
    out[#out + 1] = {
      text = st.maximized and "Restore split" or "Maximize",
      subText = st.maximized
        and ("Put " .. core.prettyName(st.apps[st.index] or "") .. " back beside "
          .. core.prettyName(st.anchor))
        or ("Fill the screen with " .. core.prettyName(st.apps[st.index] or "")),
      kind = "maximize",
    }
  end
  local names = {}
  for name in pairs(config.profiles) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    out[#out + 1] = {
      text = "Layout: " .. core.prettyName(name),
      subText = (name == st.profile and "Active · " or "") .. profileSummary(name),
      kind = "profile", name = name,
    }
  end
  return out
end

-- Subsequence match, lower is better. A hit only in the subtext ranks below any
-- hit in the text.
local function score(hay, query)
  hay = hay:lower()
  local pos, s = 1, 0
  for ch in query:lower():gmatch("%S") do
    local i = hay:find(ch, pos, true)
    if not i then return nil end
    s = s + (i - pos)
    if i == 1 or hay:sub(i - 1, i - 1):match("[%s%p]") then s = s - 2 end
    pos = i + 1
  end
  return s
end

local function filter(choices, query)
  if not query or query:match("^%s*$") then return choices end
  local ranked = {}
  for i, c in ipairs(choices) do
    local s = score(c.text, query)
    if not s then
      s = score(c.text .. " " .. c.subText, query)
      if s then s = s + 100 end
    end
    if s then ranked[#ranked + 1] = { c = c, s = s, i = i } end
  end
  table.sort(ranked, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    return a.i < b.i
  end)
  local out = {}
  for _, r in ipairs(ranked) do out[#out + 1] = r.c end
  return out
end

local current = {}

M.chooser = hs.chooser.new(function(choice)
  if not choice then return end
  if choice.kind == "app" then
    workspace.switchTo(choice.index)
  elseif choice.kind == "maximize" then
    workspace.toggleMaximize()
  elseif choice.kind == "profile" then
    layout.apply(choice.name)
  end
end)
M.chooser:placeholderText("Tessera: app or layout")
M.chooser:searchSubText(false)
M.chooser:queryChangedCallback(function(q)
  M.chooser:choices(filter(current, q))
end)

M.show = function()
  current = allChoices()
  M.chooser:query("")
  M.chooser:choices(current)
  M.chooser:show()
end

if config.keys.picker then
  hs.hotkey.bind(config.keys.switcher, config.keys.picker, M.show)
end

return M
