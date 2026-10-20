#!/usr/bin/env bash
# Full verification: parse check + targeted unit tests + race test on several seeds.
#   GODOT=/path/to/godot bash tools/run_tests.sh [seeds...]
GODOT=${GODOT:-godot}
command -v "$GODOT" >/dev/null || { echo "Godot binary not found: $GODOT"; exit 2; }
cd "$(dirname "$0")/.."
SEEDS=${*:-1 2 3 4 5 6 7}
fail=0
GODOT="$GODOT" bash tools/check_scripts.sh | grep -v '^ok' ; [ "${PIPESTATUS[0]}" = 0 ] || fail=1
echo "== unit tests"
out=$(timeout 240 "$GODOT" --headless --path . --fixed-fps 60 res://tests/unit_tests.tscn -- --test --seed=11 2>&1)
echo "$out" | grep -E "^(PASS|FAIL|UNIT)|SCRIPT ERROR" | cut -c1-400
echo "$out" | grep -q "^UNIT ALL PASS" || fail=1
for s in $SEEDS; do
  out=$(timeout 300 "$GODOT" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test --seed=$s 2>&1)
  fails=$(echo "$out" | grep -E "^FAIL|SCRIPT ERROR" | cut -c1-300)
  fin=$(echo "$out" | grep -o '"player_finish":"[^"]*"' | head -1)
  res=$(echo "$out" | grep -o '"results":\[[^]]*\]' | head -1)
  res="$res $(echo "$out" | grep -o '"landing_boosts_by_kart":\[[^]]*\]' | head -1)"
  res="$res $(echo "$out" | grep -o '"ai_wall_hits":\[[^]]*\]' | head -1) $(echo "$out" | grep -o '"ai_steer_jitter_per_s":\[[^]]*\]' | head -1) $(echo "$out" | grep -o '"ai_attack_hold_s":\[[^]]*\]' | head -1) $(echo "$out" | grep -o '"charge_fills_by_kart":\[[^]]*\]' | head -1)"
  if echo "$out" | grep -q "^ALL PASS"; then echo "seed $s: ALL PASS $fin $res"; else echo "seed $s: FAILED"; echo "$fails"; fail=1; fi
done
[ $fail = 0 ] && echo "== EVERYTHING PASSED" || echo "== FAILURES"
exit $fail
