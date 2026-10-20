#!/usr/bin/env bash
# tools/shots.sh <tag> [shots]  -> screenshots/review_fixes/<tag>_<shot>.png (Compatibility renderer)
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
  --rendering-method gl_compatibility --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy \
  res://tests/review_shots.tscn -- --tag="$1" --shots="${2:-start,pack,town,canyon,dunes,boost}" 2>&1 | grep -E "SHOT|ERROR"
