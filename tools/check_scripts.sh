#!/usr/bin/env bash
# Parse-check every GDScript in the project with Godot headless.
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
fail=0
for f in $(find scripts tests -name '*.gd' | sort); do
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR" )
  if [ -n "$out" ]; then echo "FAIL $f"; echo "$out"; fail=1; else echo "ok   $f"; fi
done
exit $fail
