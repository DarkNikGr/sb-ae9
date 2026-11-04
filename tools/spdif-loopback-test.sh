#!/bin/bash
# Verify the Sound Blaster AE-9 optical S/PDIF path with a loopback cable
# from the card's optical output to its optical input.
#
# Default mode uses the PipeWire adapter nodes ("Sound Blaster AE-9 Optical
# S/PDIF" sink -> "Sound Blaster AE-9 S/PDIF" source) at 48 kHz, which is what
# the desktop uses.  --raw drives the ALSA devices directly and tests
# 44.1 / 48 / 88.2 / 96 / 192 kHz; it only works while PipeWire is not holding
# hw:Creative,10 (for example before login, or with the input monitor closed).
#
# The S/PDIF switches are turned on for the test and restored afterwards.
# The DSP is in the path, so the result is not expected to be bit-exact; this
# checks that the link works, at the right level, rate and frequency.
#
# Usage: tools/spdif-loopback-test.sh [--quick] [--raw|--pipewire]
set -u

CARD=${AE9_CARD:-Creative}
MODE=auto
QUICK=0
for a in "$@"; do
	case "$a" in
		--quick) QUICK=1 ;;
		--raw) MODE=raw ;;
		--pipewire) MODE=pw ;;
		*) echo "unknown option: $a"; exit 2 ;;
	esac
done

if [ "$QUICK" = 1 ]; then
	RATES="48000"
else
	RATES="44100 48000 88200 96000 192000"
fi

for cmd in aplay arecord amixer python3; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "missing: $cmd"; exit 1; }
done

CARDNUM=$(awk -v id="$CARD" '$0 ~ "\\[" id { gsub(/[^0-9]/, "", $1); print $1; exit }' /proc/asound/cards)
[ -n "$CARDNUM" ] || { echo "card '$CARD' not found"; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ae9-spdif.XXXXXX") || exit 1

# The raw switch names have no simple-mixer aliases.
sw_numid() {
	amixer -c "$CARDNUM" controls 2>/dev/null |
		sed -n "s/^numid=\([0-9]*\).*name='$1'.*/\1/p" | head -1
}
pb_sw=$(sw_numid "IEC958 Playback Switch")
cap_sw=$(sw_numid "IEC958 Capture Switch")
[ -n "$pb_sw" ] && [ -n "$cap_sw" ] ||
	{ echo "IEC958 switches not found"; rm -rf "$TMP"; exit 1; }

pb_old=$(amixer -c "$CARDNUM" cget numid="$pb_sw" 2>/dev/null |
	sed -n 's/^  : values=//p' | head -1)
cap_old=$(amixer -c "$CARDNUM" cget numid="$cap_sw" 2>/dev/null |
	sed -n 's/^  : values=//p' | head -1)

restore() {
	[ -n "${pb_old:-}" ] && amixer -c "$CARDNUM" cset numid="$pb_sw" "$pb_old" >/dev/null 2>&1
	[ -n "${cap_old:-}" ] && amixer -c "$CARDNUM" cset numid="$cap_sw" "$cap_old" >/dev/null 2>&1
}
trap 'restore; rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

amixer -c "$CARDNUM" cset numid="$pb_sw" on >/dev/null
amixer -c "$CARDNUM" cset numid="$cap_sw" on >/dev/null

tone() { # rate file seconds
	python3 - "$1" "$2" "$3" <<'PY'
import sys, wave, struct, math
rate, path, dur = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
w = wave.open(path, 'wb'); w.setnchannels(2); w.setsampwidth(4); w.setframerate(rate)
for i in range(int(rate * dur)):
    v = int(0.5 * 2**31 * math.sin(2 * math.pi * 1000 * i / rate))
    w.writeframesraw(struct.pack('<ii', v, v))
w.close()
PY
}

analyze() { # file expected-rate
	python3 - "$1" "$2" <<'PY'
import sys, wave, struct, math, statistics
path, want = sys.argv[1], int(sys.argv[2])
try:
    w = wave.open(path, 'rb')
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    v = struct.unpack('<%di' % (n * ch), w.readframes(n))[::ch]
except Exception as e:
    print('ERR 0 0 0 %s' % e); sys.exit(0)
pk = max((abs(x) for x in v), default=0)
if pk < 1000:
    print('SILENT 0 0 0 rate=%d' % rate); sys.exit(0)
# Analyse the longest sustained run of 10 ms blocks: a single click at stream
# stop must not stretch the window over the silence that follows it.
bs = max(1, rate // 100)
bpk = [max((abs(x) for x in v[i:i + bs]), default=0)
       for i in range(0, len(v), bs)]
thr = 0.1 * max(bpk)
best = (0, 0); start = None
for i, p in enumerate(bpk + [0]):
    if p > thr and start is None:
        start = i
    elif p <= thr and start is not None:
        if i - start > best[1] - best[0]:
            best = (start, i)
        start = None
lo, hi = best[0] * bs, min(best[1] * bs, len(v))
seg = v[lo:hi]
# a 10 ms block starts before the tone: trim the silent edges of the run
nz = [i for i, x in enumerate(seg) if abs(x) > 0.02 * pk]
if nz:
    seg = seg[nz[0]:nz[-1] + 1]
z = [i for i in range(1, len(seg)) if seg[i - 1] < 0 <= seg[i]]
d = [z[i] - z[i - 1] for i in range(1, len(z))]
d = [x for x in d if x >= 10]          # ignore clicks / stream-stop transients
freq = rate / statistics.median(d) if d else 0
thr = 0.02 * pk; gap = worst = 0
for x in seg:
    if abs(x) < thr:
        gap += 1; worst = max(worst, gap)
    else:
        gap = 0
level = (statistics.median(bpk[best[0]:best[1]]) / 2**31
         if best[1] > best[0] else pk / 2**31)
print('%.4f %.2f %.2f %d' % (level, freq, worst * 1000.0 / rate, rate))
PY
}

pw_ids() {
	pw-dump 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
src = sink = ""
for o in d:
    p = o.get("info",{}).get("props",{})
    n = p.get("node.name","")
    if n == "alsa_input.ae9_spdif":  src = str(o["id"])
    if n == "alsa_output.ae9_spdif": sink = str(o["id"])
print(src, sink)'
}

report() { # rate peak freq gap got
	local rate=$1 peak=$2 freq=$3 gap=$4 got=$5 res=OK rate_ok
	[ "$peak" = "SILENT" ] || [ "$peak" = "ERR" ] && res="NO SIGNAL"
	if [ "$res" = OK ]; then
		[ "$got" != "$rate" ] && res="WRONG RATE"
		awk -v f="$freq" 'BEGIN { exit !(f < 980 || f > 1020) }' && res="WRONG FREQ"
		awk -v g="$gap" 'BEGIN { exit !(g > 1.0) }' && res="DROPOUT"
	fi
	[ "$res" = OK ] || FAIL=1
	rate_ok=$([ "$got" = "$rate" ] && echo yes || echo "no ($got)")
	printf '%-8s %-6s %-9s %-8s %-8s %s\n' "$rate" "$peak" "$freq" "$gap" "$rate_ok" "$res"
}

# Pick the mode: the PipeWire adapters are the normal path; raw ALSA needs the
# device to be free.
read -r PW_SRC PW_SINK <<<"$(pw_ids)"
[ "$MODE" = auto ] && { [ -n "$PW_SRC" ] && [ -n "$PW_SINK" ] && MODE=pw || MODE=raw; }
if [ "$MODE" = pw ] && { [ -z "$PW_SRC" ] || [ -z "$PW_SINK" ]; }; then
	echo "PipeWire S/PDIF nodes not found; try --raw"
	exit 1
fi
if [ "$MODE" = raw ]; then
	if ! arecord -D "hw:$CARD,10" -f S32_LE -r 48000 -c 2 -d 1 \
		"$TMP/probe.wav" >/dev/null 2>&1; then
		echo "hw:$CARD,10 is busy (the PipeWire adapters hold it)."
		echo "Close the input monitor, or use the default PipeWire mode."
		exit 1
	fi
fi

FAIL=0

if [ "$MODE" = pw ]; then
	for cmd in pw-record pw-play; do
		command -v "$cmd" >/dev/null 2>&1 || { echo "missing: $cmd"; exit 1; }
	done
	echo "mode: PipeWire adapters (follows the stream rate)"
	echo
	printf '%-8s %-6s %-9s %-8s %-8s %s\n' RATE PEAK FREQ DROPOUT RATE_OK RESULT
	for rate in $RATES; do
		tone "$rate" "$TMP/tone.wav" 1.0
		timeout 2 pw-record --target "$PW_SRC" --rate "$rate" --channels 2 \
			--format s32 "$TMP/cap.wav" >/dev/null 2>&1 &
		sleep 0.4
		pw-play --target "$PW_SINK" "$TMP/tone.wav" >/dev/null 2>&1
		wait
		set -- $(analyze "$TMP/cap.wav" "$rate")
		report "$rate" "$1" "$2" "$3" "$4"
	done
else
	play_devs=$(aplay -l 2>/dev/null |
		sed -n 's/^card [0-9]*: .*device \([0-9]*\): CA0132 Digital.*/\1/p')
	cap_devs=$(arecord -l 2>/dev/null |
		sed -n 's/^card [0-9]*: .*device \([0-9]*\): CA0132 Digital.*/\1/p')
	[ -n "$play_devs" ] && [ -n "$cap_devs" ] || { echo "no digital PCM"; exit 1; }
	# find the pair the cable connects
	PAIR=""
	for pd in $play_devs; do
		for cd in $cap_devs; do
			tone 48000 "$TMP/id.wav" 0.6
			arecord -D "hw:$CARD,${cd}" -f S32_LE -r 48000 -c 2 -d 1 \
				"$TMP/id_cap.wav" >/dev/null 2>&1 &
			sleep 0.3
			aplay -D "hw:$CARD,${pd}" -f S32_LE -r 48000 -c 2 \
				"$TMP/id.wav" >/dev/null 2>&1
			wait
			set -- $(analyze "$TMP/id_cap.wav" 48000)
			if [ "$1" != "SILENT" ] && [ "$1" != "ERR" ] &&
			   awk -v p="$1" 'BEGIN { exit !(p > 0.05) }'; then
				PAIR="$pd $cd"; break 2
			fi
		done
	done
	[ -n "$PAIR" ] || { echo "No loopback signal. Check the cable."; exit 1; }
	set -- $PAIR; PLAY_DEV=$1; CAP_DEV=$2
	echo "mode: raw ALSA, playback device $PLAY_DEV -> capture device $CAP_DEV"
	echo
	printf '%-8s %-6s %-9s %-8s %-8s %s\n' RATE PEAK FREQ DROPOUT RATE_OK RESULT
	[ "$QUICK" = 1 ] && RATES="48000" || RATES="44100 48000 88200 96000 192000"
	for rate in $RATES; do
		tone "$rate" "$TMP/tone.wav" 1.0
		arecord -D "hw:$CARD,${CAP_DEV}" -f S32_LE -r "$rate" -c 2 -d 2 \
			"$TMP/cap.wav" >/dev/null 2>&1 &
		sleep 0.4
		aplay -D "hw:$CARD,${PLAY_DEV}" -f S32_LE -r "$rate" -c 2 \
			"$TMP/tone.wav" >/dev/null 2>&1
		wait
		set -- $(analyze "$TMP/cap.wav" "$rate")
		report "$rate" "$1" "$2" "$3" "$4"
	done
fi

echo
if [ "$FAIL" = 0 ]; then
	echo "S/PDIF loopback OK."
else
	echo "S/PDIF loopback reported a problem above."
fi
exit "$FAIL"
