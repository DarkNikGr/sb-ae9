#!/bin/bash
# One-command health check for the Sound Blaster AE-9 driver.
#
# Checks the driver bring-up, the mixer controls, the PipeWire nodes and
# defaults, the capture and playback rate matrix and (optionally) the
# optical S/PDIF loopback.  It only reads and temporarily changes state:
# the graph clock force-rate and the streams are restored on exit.
#
# Usage: tools/ae9-selftest.sh [options]
#
#   --quick         test 48 kHz only and use a short loopback run
#   --no-loopback   skip the optical S/PDIF loopback test
#   --no-capture    skip the capture rate matrix
#   --no-playback   skip the playback rate matrix (no test tone)
#   --json FILE     also write a machine-readable report
#   --report FILE   also write the console output to FILE
#   -h, --help      show this help
#
# The card id defaults to "Creative"; override it with AE9_CARD.
# Exit status is 0 when every check passed (warnings and skips are fine),
# 1 when at least one check failed.
set -u

CARD=${AE9_CARD:-Creative}
QUICK=0
DO_LOOPBACK=1
DO_CAPTURE=1
DO_PLAYBACK=1
JSON=""
REPORT=""

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		--quick) QUICK=1 ;;
		--no-loopback) DO_LOOPBACK=0 ;;
		--no-capture) DO_CAPTURE=0 ;;
		--no-playback) DO_PLAYBACK=0 ;;
		--json) JSON=${2:-}; [ -n "$JSON" ] || { echo "--json needs a file" >&2; exit 2; }; shift ;;
		--report) REPORT=${2:-}; [ -n "$REPORT" ] || { echo "--report needs a file" >&2; exit 2; }; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage; exit 2 ;;
	esac
	shift
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ae9-selftest.XXXXXX") || exit 1

if [ "$QUICK" = 1 ]; then
	RATES="48000"
	LOOP_ARGS="--quick"
else
	RATES="44100 96000 192000"
	LOOP_ARGS=""
fi

declare -a R_NAME=() R_STATUS=() R_DETAIL=()
FAIL=0
WARN=0

record() { # name status detail
	R_NAME+=("$1")
	R_STATUS+=("$2")
	R_DETAIL+=("$(printf '%s' "$3" | tr '\t\n' '  ')")
}

pass() { record "$1" OK "$2"; printf '[ OK ] %s%s\n' "$1" "${2:+ — $2}"; }
fail() { record "$1" FAIL "$2"; FAIL=1; printf '[FAIL] %s%s\n' "$1" "${2:+ — $2}"; }
warn() { record "$1" WARN "$2"; WARN=$((WARN + 1)); printf '[WARN] %s%s\n' "$1" "${2:+ — $2}"; }
skip() { record "$1" SKIP "$2"; printf '[SKIP] %s%s\n' "$1" "${2:+ — $2}"; }
info() { record "$1" INFO "$2"; printf '[INFO] %s%s\n' "$1" "${2:+ — $2}"; }
section() { printf '\n== %s ==\n' "$1"; }

[ -n "$REPORT" ] && exec > >(tee "$REPORT") 2>&1

ORIG_FORCE=""
restore_force() {
	if [ -n "$ORIG_FORCE" ] && command -v pw-metadata >/dev/null 2>&1; then
		pw-metadata -n settings 0 clock.force-rate "$ORIG_FORCE" >/dev/null 2>&1
	fi
}
cleanup() {
	jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
	restore_force
	rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

have() { command -v "$1" >/dev/null 2>&1; }

card_number() {
	awk -v id="[$CARD" 'index($0, id) { gsub(/[^0-9]/, "", $1); print $1; exit }' \
		/proc/asound/cards 2>/dev/null
}

running_hw_rate() { # c|p [pcm-device]
	local dir=$1 dev=${2:-} f rate
	if [ -n "$dev" ]; then
		f=/proc/asound/"$CARD"/pcm"$dev""$dir"/sub0/hw_params
		[ -r "$f" ] || return 0
		sed -n 's/^rate: \([0-9]*\).*/\1/p' "$f" | head -1
		return 0
	fi
	for f in /proc/asound/"$CARD"/pcm*"$dir"/sub0/hw_params; do
		[ -r "$f" ] || continue
		# An unused PCM reads "closed"; an open one lists access/format/rate.
		rate=$(sed -n 's/^rate: \([0-9]*\).*/\1/p' "$f" | head -1)
		[ -n "$rate" ] && { printf '%s' "$rate"; return; }
	done
}

set_force_rate() {
	local want=$1 cur i
	[ -n "${HAS_PW_METADATA:-}" ] || return 1
	pw-metadata -n settings 0 clock.force-rate "$want" >/dev/null 2>&1 || return 1
	for i in $(seq 1 40); do
		cur=$(pw-metadata -n settings 2>/dev/null |
			sed -n "s/.*key:'clock.force-rate' value:'\([0-9]*\)'.*/\1/p" | head -1)
		[ "$cur" = "$want" ] && { sleep 0.2; return 0; }
		sleep 0.05
	done
	return 1
}

nodes_tsv() {
	pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    props = (o.get("info") or {}).get("props") or {}
    cls = props.get("media.class", "")
    if not cls.startswith("Audio/"):
        continue
    print("%s\t%s\t%s\t%s" % (o.get("id", ""), cls,
                              props.get("node.name", ""),
                              props.get("node.description", "")))
' > "$TMP/nodes.tsv"
}

node_id() { # class description-substring
	awk -F'\t' -v cls="$1" -v want="$2" \
		'index($2, cls) == 1 && index($4, want) { print $1; exit }' \
		"$TMP/nodes.tsv"
}

tone() { # rate file seconds
	python3 - "$1" "$2" "$3" <<'PY'
import sys, wave, struct, math
rate, path, dur = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
w = wave.open(path, 'wb')
w.setnchannels(2)
w.setsampwidth(4)
w.setframerate(rate)
for i in range(int(rate * dur)):
    v = int(0.15 * 2**31 * math.sin(2 * math.pi * 1000 * i / rate))
    w.writeframesraw(struct.pack('<ii', v, v))
w.close()
PY
}

run_loopback() {
	local out rc
	if [ ! -x "$ROOT/tools/spdif-loopback-test.sh" ]; then
		skip "S/PDIF loopback" "tools/spdif-loopback-test.sh not found"
		return
	fi
	out=$("$ROOT/tools/spdif-loopback-test.sh" $LOOP_ARGS 2>&1)
	rc=$?
	if [ "$rc" = 0 ]; then
		pass "S/PDIF loopback" "$(printf '%s\n' "$out" | tail -1)"
	else
		fail "S/PDIF loopback" "$(printf '%s\n' "$out" | tail -3 | tr '\n' ' ')"
		printf '%s\n' "$out" | sed 's/^/       /'
	fi
}

capture_matrix() { # label node pcm-device rates
	local label=$1 node=$2 dev=$3 rates=$4 rate hw okr="" badr="" i pid
	if [ -z "$node" ]; then
		skip "capture: $label" "PipeWire source not found"
		return
	fi
	for rate in $rates; do
		set_force_rate "$rate" || {
			skip "capture: $label" "cannot set the graph rate"
			return
		}
		pw-record --target "$node" --rate "$rate" --channels 2 \
			--format s32 "$TMP/cap.wav" >/dev/null 2>&1 &
		pid=$!
		hw=""
		for i in $(seq 1 60); do
			sleep 0.05
			hw=$(running_hw_rate c "$dev")
			[ "$hw" = "$rate" ] && break
		done
		kill "$pid" 2>/dev/null
		wait "$pid" 2>/dev/null
		# Let the PCM close before the next stream so a stale rate is not read.
		for i in $(seq 1 40); do
			[ -z "$(running_hw_rate c "$dev")" ] && break
			sleep 0.05
		done
		if [ "$hw" = "$rate" ]; then
			okr+="$rate "
		else
			badr+="$rate(${hw:-none}) "
		fi
	done
	okr=${okr% }
	badr=${badr% }
	if [ -z "$badr" ]; then
		pass "capture: $label" "hardware rate $okr"
	else
		fail "capture: $label" "ok: ${okr:-none}; bad: $badr"
	fi
}

playback_matrix() { # label node pcm-device rates
	local label=$1 node=$2 dev=$3 rates=$4 rate hw okr="" badr="" i pid
	if [ -z "$node" ]; then
		skip "playback: $label" "PipeWire sink not found"
		return
	fi
	for rate in $rates; do
		set_force_rate "$rate" || {
			skip "playback: $label" "cannot set the graph rate"
			return
		}
		tone "$rate" "$TMP/tone-$rate.wav" 0.8
		pw-play --target "$node" "$TMP/tone-$rate.wav" >/dev/null 2>&1 &
		pid=$!
		hw=""
		for i in $(seq 1 40); do
			sleep 0.05
			hw=$(running_hw_rate p "$dev")
			[ "$hw" = "$rate" ] && break
		done
		wait "$pid" 2>/dev/null
		for i in $(seq 1 40); do
			[ -z "$(running_hw_rate p "$dev")" ] && break
			sleep 0.05
		done
		if [ "$hw" = "$rate" ]; then
			okr+="$rate "
		else
			badr+="$rate(${hw:-none}) "
		fi
	done
	okr=${okr% }
	badr=${badr% }
	if [ -z "$badr" ]; then
		pass "playback: $label" "hardware rate $okr"
	else
		fail "playback: $label" "ok: ${okr:-none}; bad: $badr"
	fi
}

# ---------------------------------------------------------------------------
# Driver and card
# ---------------------------------------------------------------------------
printf 'AE-9 selftest — %s — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(uname -r)"

section "Driver"
if [ -d /sys/module/snd_hda_codec_ca0132 ]; then
	pass "module loaded" "$(modinfo -F filename snd_hda_codec_ca0132 2>/dev/null || echo snd_hda_codec_ca0132)"
else
	fail "module loaded" "snd_hda_codec_ca0132 is not loaded"
fi

PARAMS=/sys/module/snd_hda_codec_ca0132/parameters
if [ -d "$PARAMS" ]; then
	p_direct=$(cat "$PARAMS/ae9_direct" 2>/dev/null || echo '?')
	p_capture=$(cat "$PARAMS/ae9_capture" 2>/dev/null || echo '?')
	p_mic=$(cat "$PARAMS/ae9_mic" 2>/dev/null || echo '?')
	p_poll=$(cat "$PARAMS/ae9_acm_poll" 2>/dev/null || echo '?')
	info "module parameters" "ae9_direct=$p_direct ae9_capture=$p_capture ae9_mic=$p_mic ae9_acm_poll=$p_poll"
	if [ "$p_direct" = "Y" ]; then
		warn "Direct Mode default" "ae9_direct=1 (opt-in; the module default is 0)"
	fi
else
	skip "module parameters" "parameters directory not present"
fi

CARDNUM=$(card_number)
if [ -z "$CARDNUM" ]; then
	fail "card $CARD" "not found in /proc/asound/cards"
	printf '\nSummary: %d failed before the card was available.\n' "$FAIL"
	exit 1
fi
card_desc=$(awk -v n="$CARDNUM" '$1 == n { sub(/^[^]]*]: */, ""); print; exit }' /proc/asound/cards)
pass "card $CARD" "card $CARDNUM, ${card_desc:-present}"

# ---------------------------------------------------------------------------
# Bring-up log
# ---------------------------------------------------------------------------
section "Bring-up"
LOG=$(journalctl -k -b --no-pager 2>/dev/null || true)
[ -n "$LOG" ] || LOG=$(dmesg 2>/dev/null || true)
if [ -z "$LOG" ]; then
	skip "kernel log" "journalctl and dmesg are both unavailable"
else
	overlay=$(printf '%s\n' "$LOG" | grep -m1 'overlay readback' || true)
	load_failed=$(printf '%s\n' "$LOG" | grep -m1 'overlay load failed' || true)
	if [ -n "$load_failed" ]; then
		fail "DSP overlay" "$(printf '%s' "$load_failed" | sed 's/.*AE-9: //')"
	elif [ -n "$overlay" ]; then
		pass "DSP overlay" "$(printf '%s' "$overlay" | sed 's/.*AE-9: //')"
	else
		warn "DSP overlay" "no overlay readback line in this boot"
	fi
	if printf '%s\n' "$LOG" | grep -Eq 'AE-9.*(DSP did not boot|DSP boot failed|initialize DSP failed|DSP boot timeout)'; then
		fail "DSP boot" "$(printf '%s\n' "$LOG" | grep -Em1 'AE-9.*(DSP did not boot|DSP boot failed|initialize DSP failed|DSP boot timeout)' | sed 's/.*AE-9: //')"
	else
		pass "DSP boot" "no boot errors in this boot"
	fi
	if printf '%s\n' "$LOG" | grep -q 'AE-9: 8051 router hooks installed'; then
		pass "8051 router hooks" "installed"
	else
		warn "8051 router hooks" "no install line in this boot"
	fi
fi

# ---------------------------------------------------------------------------
# Mixer controls and current state
# ---------------------------------------------------------------------------
section "Mixer"
missing=""
for c in Master PCM Surround "Headphone+LO" "AE-9 Output" "Enable OutFX" "AE-9 Direct Mode"; do
	amixer -c "$CARDNUM" scontrols 2>/dev/null | grep -Fq "'$c'" || missing+=" $c"
done
for c in "IEC958 Playback Switch" "IEC958 Capture Switch"; do
	amixer -c "$CARDNUM" controls 2>/dev/null | grep -Fq "name='$c'" || missing+=" $c"
done
if [ -z "$missing" ]; then
	pass "required controls" "9 present"
else
	fail "required controls" "missing:$missing"
fi

master_line=$(amixer -c "$CARDNUM" sget Master 2>/dev/null | grep -m1 -E 'Mono: Playback|Front Left: Playback' | sed 's/^ *//')
if [ -n "$master_line" ]; then
	case "$master_line" in
		*'[off]'*) warn "master volume" "$master_line" ;;
		*) pass "master volume" "$master_line" ;;
	esac
else
	warn "master volume" "Master control not readable"
fi

out_sel=$(amixer -c "$CARDNUM" sget 'AE-9 Output' 2>/dev/null | sed -n "s/.*Item0: '\(.*\)'/\1/p")
if [ -n "$out_sel" ]; then
	pass "output selector" "$out_sel"
else
	warn "output selector" "AE-9 Output not readable"
fi

direct=$(amixer -c "$CARDNUM" sget 'AE-9 Direct Mode' 2>/dev/null | grep -o '\[on\]\|\[off\]' | head -1)
case "$direct" in
	'[off]') pass "Direct Mode" "off" ;;
	'[on]') warn "Direct Mode" "on (opt-in, the session default is off)" ;;
	*) warn "Direct Mode" "not readable" ;;
esac

acm=$(journalctl -k -b --no-pager 2>/dev/null | grep -m1 'ACM.*(present\|online\|ready)' || true)
if [ -n "$acm" ]; then
	pass "ACM" "$(printf '%s' "$acm" | sed 's/.*AE-9: //')"
else
	info "ACM" "no explicit ACM presence line in this boot"
fi

# ---------------------------------------------------------------------------
# PipeWire nodes and defaults
# ---------------------------------------------------------------------------
section "PipeWire"
if have pw-dump; then
	nodes_tsv || true
else
	: > "$TMP/nodes.tsv"
fi

if [ ! -s "$TMP/nodes.tsv" ]; then
	skip "PipeWire nodes" "pw-dump is unavailable or PipeWire is not running"
else
	analog_sink=$(node_id Audio/Sink "Sound Blaster AE-9 Output")
	optical_sink=$(node_id Audio/Sink "Sound Blaster AE-9 Optical S/PDIF")
	mic_src=$(node_id Audio/Source "Sound Blaster AE-9 Microphone")
	linein_src=$(node_id Audio/Source "Sound Blaster AE-9 Line In")
	wuh_src=$(node_id Audio/Source "Sound Blaster AE-9 What U Hear")
	spdif_src=$(node_id Audio/Source "Sound Blaster AE-9 S/PDIF")

	[ -n "$analog_sink" ] && pass "sink: analog" "id $analog_sink" ||
		fail "sink: analog" "Sound Blaster AE-9 Output not found"
	[ -n "$optical_sink" ] && pass "sink: optical" "id $optical_sink" ||
		warn "sink: optical" "missing (install install/20-ae9-inputs.conf)"
	[ -n "$mic_src" ] && pass "source: microphone" "id $mic_src" ||
		fail "source: microphone" "Sound Blaster AE-9 Microphone not found"
	for pair in "linein|$linein_src|Line In" "wuh|$wuh_src|What U Hear" "spdif|$spdif_src|S/PDIF"; do
		key=${pair%%|*}; rest=${pair#*|}; id=${rest%%|*}; label=${rest#*|}
		[ -n "$id" ] && pass "source: $label" "id $id" ||
			warn "source: $label" "missing (install install/20-ae9-inputs.conf)"
	done

	if have wpctl; then
		def_sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | sed -n 's/.*node.description = "\(.*\)"/\1/p' | head -1)
		def_src=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | sed -n 's/.*node.description = "\(.*\)"/\1/p' | head -1)
		case "$def_sink" in
			*"Sound Blaster AE-9"*) pass "default sink" "$def_sink" ;;
			*) warn "default sink" "${def_sink:-not set}" ;;
		esac
		case "$def_src" in
			*"Sound Blaster AE-9"*) pass "default source" "$def_src" ;;
			*) warn "default source" "${def_src:-not set}" ;;
		esac
	else
		skip "default sink/source" "wpctl not found"
	fi
fi

# Force-rate is needed for the matrix; save and restore it.
HAS_PW_METADATA=""
if have pw-metadata; then
	HAS_PW_METADATA=1
	ORIG_FORCE=$(pw-metadata -n settings 2>/dev/null |
		sed -n "s/.*key:'clock.force-rate' value:'\([0-9]*\)'.*/\1/p" | head -1)
	[ -n "$ORIG_FORCE" ] || ORIG_FORCE=0
fi

# ---------------------------------------------------------------------------
# Capture and playback rate matrix
# ---------------------------------------------------------------------------
if [ "$DO_CAPTURE" = 1 ]; then
	section "Capture"
	if [ -z "$HAS_PW_METADATA" ] || ! have pw-record; then
		skip "capture matrix" "pw-record or pw-metadata not found"
	elif [ ! -s "$TMP/nodes.tsv" ]; then
		skip "capture matrix" "PipeWire is not running"
	else
		capture_matrix "Line In" "$linein_src" 4 "$RATES"
		if [ "$QUICK" = 1 ]; then
			capture_matrix "What U Hear" "$wuh_src" 2 "48000"
			capture_matrix "Microphone" "$mic_src" 0 "48000"
		else
			capture_matrix "What U Hear" "$wuh_src" 2 "44100 96000"
			capture_matrix "Microphone" "$mic_src" 0 "44100 96000"
		fi
		capture_matrix "S/PDIF" "$spdif_src" 10 "$RATES"
	fi
fi

if [ "$DO_PLAYBACK" = 1 ]; then
	section "Playback"
	if [ -z "$HAS_PW_METADATA" ] || ! have pw-play; then
		skip "playback matrix" "pw-play or pw-metadata not found"
	elif [ ! -s "$TMP/nodes.tsv" ]; then
		skip "playback matrix" "PipeWire is not running"
	else
		info "playback tone" "a short 1 kHz tone is played on the analog sink"
		playback_matrix "analog" "$analog_sink" 0 "$RATES"
		[ -n "$optical_sink" ] && playback_matrix "optical" "$optical_sink" 10 "$RATES"
	fi
fi

# ---------------------------------------------------------------------------
# Optical loopback
# ---------------------------------------------------------------------------
if [ "$DO_LOOPBACK" = 1 ]; then
	section "Optical S/PDIF"
	run_loopback
fi

# ---------------------------------------------------------------------------
# GUI control read (optional)
# ---------------------------------------------------------------------------
if [ -x "$ROOT/tools/ae9-fx" ] && python3 -c 'import gi' >/dev/null 2>&1; then
	gui_out=$(timeout 45 "$ROOT/tools/ae9-fx" --selftest 2>&1)
	gui_rc=$?
	if [ "$gui_rc" = 0 ]; then
		pass "GUI control read" "$(printf '%s\n' "$gui_out" | grep -m1 'acm selector' || echo 'selftest ok')"
	else
		fail "GUI control read" "ae9-fx --selftest exited $gui_rc"
	fi
fi

# ---------------------------------------------------------------------------
# Summary and reports
# ---------------------------------------------------------------------------
ok=0
wcount=0
scount=0
fcount=0
for s in "${R_STATUS[@]}"; do
	case "$s" in
		OK) ok=$((ok + 1)) ;;
		WARN) wcount=$((wcount + 1)) ;;
		SKIP) scount=$((scount + 1)) ;;
		FAIL) fcount=$((fcount + 1)) ;;
	esac
done

printf '\nSummary: %d OK, %d warning(s), %d skipped, %d failed\n' \
	"$ok" "$wcount" "$scount" "$fcount"
[ "$fcount" = 0 ] && echo "AE-9 selftest passed." || echo "AE-9 selftest found a problem above."

if [ -n "$JSON" ]; then
	: > "$TMP/results.tsv"
	for i in "${!R_NAME[@]}"; do
		printf '%s\t%s\t%s\n' "${R_NAME[$i]}" "${R_STATUS[$i]}" "${R_DETAIL[$i]}" \
			>> "$TMP/results.tsv"
	done
	META_KERNEL=$(uname -r) \
	META_MODULE=$(modinfo -F filename snd_hda_codec_ca0132 2>/dev/null || true) \
	META_CARD="$CARD" \
	python3 - "$JSON" "$TMP/results.tsv" <<'PY'
import datetime, json, os, sys

path, tsv = sys.argv[1], sys.argv[2]
results = []
with open(tsv) as f:
    for line in f:
        name, status, detail = line.rstrip('\n').split('\t')
        results.append({"check": name, "status": status, "detail": detail})

report = {
    "generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "kernel": os.environ.get("META_KERNEL", ""),
    "module": os.environ.get("META_MODULE", ""),
    "card": os.environ.get("META_CARD", ""),
    "ok": all(r["status"] != "FAIL" for r in results),
    "results": results,
}
with open(path, "w") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY
	echo "JSON report: $JSON"
fi

exit "$FAIL"
