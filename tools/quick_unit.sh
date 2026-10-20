#!/usr/bin/env bash
# parse-check the unit test file, then run it (fails fast on parse errors)
GODOT=${GODOT:-godot}; cd "$(dirname "$0")/.."
err=$("$GODOT" --headless --path . --check-only --script res://tests/unit_tests.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | grep -v GameConfig)
[ -n "$err" ] && { echo "$err"; exit 1; }
for f in $(git status --short | awk '{print $2}' | grep -E '\.gd$'; git status --short | awk '{print $2}' | grep '/$' | xargs -r -I{} find {} -name "*.gd"); do
  e=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | grep -v -E "GameConfig|Failed to compile depended|Compilation failed|referenced non-existent resource")
  [ -n "$e" ] && { echo "$f: $e"; exit 1; }
done
timeout 240 "$GODOT" --headless --path . --fixed-fps 60 res://tests/unit_tests.tscn -- --test --seed=11 2>&1 | grep -E "^(PASS|FAIL|UNIT)|SCRIPT ERROR" | cut -c1-700
