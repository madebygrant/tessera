#!/usr/bin/env bash

sketchybar --add event tessera_switcher \
           --add item tessera left \
           --set tessera icon="" \
                         label="—" \
                         label.padding_right=12 \
                         script="$PLUGIN_DIR/tessera.sh" \
           --subscribe tessera tessera_switcher front_app_switched mouse.scrolled

# The icon slot carries text (the profile), so give it the label's font and
# baseline rather than the bar's icon font.
LABEL_FONT=$(sketchybar --query tessera | sed -n '/"label"/,/}/s/.*"font": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$LABEL_FONT" ] && sketchybar --set tessera icon.font="$LABEL_FONT" icon.y_offset=0

# The bar restarts independently of Hammerspoon, so ask it for current state.
# Subshell because this file is sourced; launchd's PATH may not carry hs.
(
  HS=$(command -v hs) || HS=/opt/homebrew/bin/hs
  [ -x "$HS" ] || HS=/usr/local/bin/hs
  [ -x "$HS" ] && "$HS" -c 'require("tessera.layout-workspace").pushToBar()'
) >/dev/null 2>&1 &
