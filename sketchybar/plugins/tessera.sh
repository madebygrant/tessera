#!/usr/bin/env bash

# Optional: a shared palette file, if your bar config has one.
[ -f "$CONFIG_DIR/shared.sh" ] && source "$CONFIG_DIR/shared.sh"

# Export TESSERA_LABEL_COLOR from your own config to theme this.
LABEL_COLOR="${TESSERA_LABEL_COLOR:-0xffffffff}"

STATE="${TMPDIR:-/tmp}/sketchybar_tessera"
FRONT_STATE="${TMPDIR:-/tmp}/sketchybar_tessera_front"

# Two senders race here in separate processes, and a switch fires both at once.
# Rename so a reader never lands on a half-written file.
write_state () {
  local dest=$1; shift
  local tmp="$dest.$$"
  printf '%s\n' "$@" > "$tmp" && mv -f "$tmp" "$dest"
}

case "$SENDER" in
  tessera_switcher)
    [ -z "$PROFILE" ] && exit 0
    write_state "$STATE" "$PROFILE" "$INDEX" "$COUNT" "$MAXIMIZED" "$APP_NAME" "$ANCHOR_NAME"
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
{ read -r PROFILE; read -r INDEX; read -r COUNT; read -r MAXIMIZED; read -r APP_NAME; read -r ANCHOR_NAME; } < "$STATE"
FRONT=$(cat "$FRONT_STATE" 2>/dev/null)

# Split camelCase refs before upcasing: agenticDev -> AGENTIC DEV.
LABEL=$(echo "$PROFILE" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g' | tr '[:lower:]' '[:upper:]')

case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

# The number means something only inside the layout, and only if a profile
# cycles anything at all.
if [ "$COUNT" -gt 0 ] && { [ "$FRONT" = "$APP_NAME" ] || [ "$FRONT" = "$ANCHOR_NAME" ]; }; then
  LABEL="${LABEL} ${INDEX}/${COUNT}"
fi

sketchybar --set "$NAME" \
           icon="" \
           label="$LABEL" \
           label.color="$LABEL_COLOR"
