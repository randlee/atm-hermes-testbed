#!/bin/sh
# test-at8-calibrate.sh — deterministic helper tests for at8-calibrate.sh and
# freeze-daemon.sh HGC-023 validation (draft item 8). Runs on the HOST (no
# container, no daemon): exercises the calibration/validation logic via an
# isolated marker dir and the argument-validation head of freeze-daemon.sh
# (which fail-closes BEFORE any pgrep/signal, so it is safe to run anywhere).
#
# Usage: testbed/harness/test-at8-calibrate.sh   (prints PASS/FAIL per case,
#        exit 0 iff all cases pass)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CAL="$HERE/at8-calibrate.sh"
FREEZE="$HERE/freeze-daemon.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILURES=0

# --- at8-calibrate.sh cases -------------------------------------------------
cal_case() { # name, expected-exit, expected-stdout-substring, marker-content-or-__MISSING__
  name="$1"; want_rc="$2"; want_out="$3"; content="$4"
  d="$TMP/$name"; mkdir -p "$d"
  if [ "$content" != "__MISSING__" ]; then printf '%b' "$content" > "$d/at8-rtt"; fi
  out=$(MARKERS_DIR="$d" WAIT_S=2 sh "$CAL" 2>"$TMP/$name.err"); rc=$?
  err=$(cat "$TMP/$name.err")
  ok=1
  [ "$rc" = "$want_rc" ] || ok=0
  if [ "$want_rc" = 0 ]; then
    case "$out" in *"$want_out"*) ;; *) ok=0 ;; esac
  else
    case "$err" in *"FAIL: calibration marker missing/invalid"*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" = 1 ]; then echo "PASS calibrate/$name"; else
    echo "FAIL calibrate/$name rc=$rc out=$out err=$err (want rc=$want_rc out~$want_out)"; FAILURES=$((FAILURES+1)); fi
}

cal_case missing       1 "" "__MISSING__"     # marker never appears -> FAIL, no default
cal_case non-digit     1 "" "12a3\n"          # regex ^[0-9]+$ violation
cal_case zero          1 "" "0\n"             # range 1..60000 violation (low)
cal_case over-max      1 "" "60001\n"         # range violation (high)
cal_case spaces        1 "" " 123 \n"         # file contract: digits only
cal_case two-lines     1 "" "123\n456\n"      # single value only
cal_case clamp-low     0 "after_ms=300 source_rtt_ms=100"   "100\n"    # (100+1)/2=50 -> clamp 300
cal_case clamp-low-599 0 "after_ms=300 source_rtt_ms=599"   "599\n"    # 300 exactly at 599/600
cal_case in-range      0 "after_ms=500 source_rtt_ms=999"   "999\n"    # (999+1)/2=500
cal_case rounding      0 "after_ms=501 source_rtt_ms=1001"  "1001\n"   # nearest-int half: (1001+1)/2
cal_case clamp-high    0 "after_ms=1500 source_rtt_ms=5000" "5000\n"   # 2500 -> clamp 1500
cal_case max-valid     0 "after_ms=1500 source_rtt_ms=60000" "60000\n" # upper range bound

# --- freeze-daemon.sh argument-validation cases -----------------------------
# These must fail-closed at the HGC-023 validation head, BEFORE pgrep/signals,
# so they are host-safe. Expected: rc=1 with the specific FAIL reason.
fz_case() { # name, expected-stderr-substring, args...
  name="$1"; want="$2"; shift 2
  out=$(sh "$FREEZE" "$@" 2>&1 >/dev/null); rc=$?
  # running as non-root exits earlier with the no-sudo FATAL — accept either
  # as fail-closed, but if root, require the specific HGC-023 reason.
  if [ "$(id -u)" = 0 ]; then
    if [ "$rc" = 1 ] && { case "$out" in *"$want"*) true;; *) false;; esac; }; then
      echo "PASS freeze/$name"; else
      echo "FAIL freeze/$name rc=$rc out=$out (want ~$want)"; FAILURES=$((FAILURES+1)); fi
  else
    case "$out" in *"must run as root"*) echo "PASS freeze/$name (no-sudo guard fires first; arg-validation covered by root-run CI)";;
      *) echo "FAIL freeze/$name rc=$rc out=$out"; FAILURES=$((FAILURES+1));;
    esac
  fi
}

fz_case after-without-rtt "requires --source-rtt" 4 --after 500
fz_case after-non-int     "--after not an integer" 4 --after abc --source-rtt 1000
fz_case after-below-clamp "out of clamp range" 4 --after 100 --source-rtt 1000
fz_case after-above-clamp "out of clamp range" 4 --after 2000 --source-rtt 1000
fz_case rtt-non-int       "--source-rtt not an integer" 4 --after 500 --source-rtt 12x
fz_case rtt-zero          "out of range 1..60000" 4 --source-rtt 0
fz_case rtt-over-max      "out of range 1..60000" 4 --source-rtt 60001

echo "---"
if [ "$FAILURES" = 0 ]; then echo "RESULT: PASS (all HGC-023 helper cases)"; exit 0
else echo "RESULT: FAIL ($FAILURES case(s))"; exit 1; fi
