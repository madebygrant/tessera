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

# The bar restarts independently of Tessera, so ask it for current state.
# Subshell because this file is sourced. At login the bar may start first;
# Tessera pushes on launch, so a missing app is fine.
(
  pgrep -xq Tessera || exit 0
  T="${TESSERA_BIN:-$HOME/Applications/Tessera.app/Contents/MacOS/Tessera}"
  [ -x "$T" ] && "$T" push
) >/dev/null 2>&1 &
