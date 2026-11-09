#!/usr/bin/env bash

# Optional: a shared palette file, if your bar config has one.
[ -f "$CONFIG_DIR/shared.sh" ] && source "$CONFIG_DIR/shared.sh"

# Export TESSERA_LABEL_COLOR from your own config to theme this.
LABEL_COLOR="${TESSERA_LABEL_COLOR:-0xffffffff}"

STATE="${TMPDIR:-/tmp}/sketchybar_tessera"
FRONT_STATE="${TMPDIR:-/tmp}/sketchybar_tessera_front"

# Backgrounded with a timeout, so a busy Hammerspoon can't stall the bar.
hs_run () {
  local HS
  HS=$(command -v hs) || HS=/opt/homebrew/bin/hs
  [ -x "$HS" ] || HS=/usr/local/bin/hs
  [ -x "$HS" ] && "$HS" -t 5 -c "$1" >/dev/null 2>&1 &
}

# Two senders race here in separate processes, and a switch fires both at once.
# Rename so a reader never lands on a half-written file.
write_state () {
  local dest=$1; shift
  local tmp="$dest.$$"
  printf '%s\n' "$@" > "$tmp" && mv -f "$tmp" "$dest"
}

# heliumDev -> Helium Dev, matching core.prettyName on the Hammerspoon side.
pretty () {
  echo "$1" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g' \
            | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'
}

case "$SENDER" in
  mouse.clicked)
    # Deferred so the IPC call returns before the chooser grabs focus, or the
    # hs CLI aborts.
    hs_run 'hs.timer.doAfter(0, require("tessera").picker)'
    exit 0
    ;;
  mouse.scrolled)
    # Hammerspoon throttles the burst a trackpad sends.
    case "${SCROLL_DELTA:-0}" in
      -*) hs_run 'require("tessera").cycle(1)' ;;
      0)  ;;
      *)  hs_run 'require("tessera").cycle(-1)' ;;
    esac
    exit 0
    ;;
  tessera_switcher)
    [ -z "$PROFILE" ] && exit 0
    write_state "$STATE" "$PROFILE" "$INDEX" "$COUNT" "$MAXIMIZED" "$APP_NAME" "$ANCHOR_NAME" "$APP"
    # front_app_switched lands after this, so trust the switcher's own focus.
    [ "$FOCUSED" = "true" ] && write_state "$FRONT_STATE" "$APP_NAME"
    ;;
  front_app_switched)
    write_state "$FRONT_STATE" "$INFO"
    ;;
esac

[ -f "$STATE" ] || exit 0
# MAXIMIZED goes unrendered since the icon stopped branching on it; held in
# position so restoring that needs no state-file migration.
{ read -r PROFILE; read -r INDEX; read -r COUNT; read -r MAXIMIZED; read -r APP_NAME; read -r ANCHOR_NAME; read -r APP; } < "$STATE"
FRONT=$(cat "$FRONT_STATE" 2>/dev/null)

# Split camelCase refs before upcasing: agenticDev -> AGENTIC DEV.
LABEL=$(echo "$PROFILE" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g' | tr '[:lower:]' '[:upper:]')

case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

# Only inside the layout. An old state file without APP falls back to the number.
if [ "$COUNT" -gt 0 ] && { [ "$FRONT" = "$APP_NAME" ] || [ "$FRONT" = "$ANCHOR_NAME" ]; }; then
  if [ -n "$APP" ]; then
    LABEL="${LABEL} · $(pretty "$APP")"
  else
    LABEL="${LABEL} ${INDEX}/${COUNT}"
  fi
fi

sketchybar --set "$NAME" \
           icon="" \
           label="$LABEL" \
           label.color="$LABEL_COLOR"
