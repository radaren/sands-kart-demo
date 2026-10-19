#!/usr/bin/env bash
# Parse-check every GDScript in the project with Godot headless.
# (autoload identifiers such as GameConfig are unknown in --script mode and are ignored)
GODOT=${GODOT:-godot}
command -v "$GODOT" >/dev/null || { echo "Godot binary not found: $GODOT (set GODOT=/path/to/godot)"; exit 2; }
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
fail=0
for f in $(find scripts tests -name '*.gd' | sort); do
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR" | grep -v -E "GameConfig|Failed to compile depended|Compilation failed|referenced non-existent resource" )
  if [ -n "$out" ]; then echo "FAIL $f"; echo "$out"; fail=1; else echo "ok   $f"; fi
done
exit $fail
