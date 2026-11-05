#!/usr/bin/env bash
# Keep the AE-9's DSP speaker layout ("Surround Channel Config") and the
# PipeWire card profile in sync.  They live in different layers: the mixer
# control is handled by the codec driver, while the profile (analog-stereo,
# analog-surround-51, ...) is created by the desktop's ALSA profile set.
# Changing either one updates the other, so the user only has to pick the
# layout once.
#
# The profile is treated as the master at startup: the desktop restores the
# last selected profile, and the mixer control follows it.  After that, a
# change on either side is propagated.
set -u

CARD=${AE9_CARD:-Creative}
INTERVAL=${AE9_SYNC_INTERVAL:-2}

log() { printf '%s ae9-profile-sync: %s\n' "$(date '+%H:%M:%S')" "$*"; }

card_num() {
	awk -v id="[$CARD" 'index($0, id) { gsub(/[^0-9]/, "", $1); print $1; exit }' \
		/proc/asound/cards 2>/dev/null
}

get_cfg() {
	amixer -c "$CARD" sget 'Surround Channel Config' 2>/dev/null |
		sed -n "s/.*Item0: '\(.*\)'/\1/p" | head -1
}

# Search for the AE-9 PipeWire device and print "<id>|<active profile>".
dev_active() {
	pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Device":
        continue
    if p.get("device.vendor.id") != "0x1102" or p.get("device.product.id") != "0x0010":
        continue
    params = (o.get("info") or {}).get("params") or {}
    active = ""
    for e in params.get("Profile") or []:
        active = e.get("name", "")
    print(str(o["id"]) + "|" + active)
    break
'
}

# Print the index for the profile whose name contains $1.  Prefer the variant
# that keeps the analog microphone input.
profile_index() {
	pw-dump 2>/dev/null | python3 -c '
import json, sys
needle = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Device":
        continue
    if p.get("device.vendor.id") != "0x1102" or p.get("device.product.id") != "0x0010":
        continue
    profs = [e for e in ((o.get("info") or {}).get("params") or {}).get("EnumProfile") or []
             if needle in (e.get("name") or "")]
    for e in profs:
        if "input:analog-stereo" in e.get("name", ""):
            print(e["index"]); sys.exit(0)
    if profs:
        print(profs[0]["index"])
    break
' "$1"
}

profile_for_cfg() {
	case "$1" in
		2.0)  echo "analog-stereo"
		      ;;
		2.1)  echo "analog-surround-21"
		      ;;
		4.0)  echo "analog-surround-40"
		      ;;
		4.1)  echo "analog-surround-41"
		      ;;
		5.1)  echo "analog-surround-51"
		      ;;
		*)    echo "" ;;
	esac
}

cfg_for_profile() {
	case "$1" in
		*surround-51*) echo "5.1" ;;
		*surround-41*) echo "4.1" ;;
		*surround-40*) echo "4.0" ;;
		*surround-21*) echo "2.1" ;;
		*analog-stereo*) echo "2.0" ;;
		*) echo "" ;;
	esac
}

set_profile() { # dev profile-key
	local idx
	idx=$(profile_index "$2")
	[ -n "$idx" ] || return 1
	wpctl set-profile "$1" "$idx" 2>/dev/null || return 1
	log "profile -> $2 (index $idx)"
	# Let ACP create the new sink, then make it the default.
	sleep 1
	set_default_sink
}

set_default_sink() {
	local line id name
	line=$(pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Sink":
        continue
    n = p.get("node.name", "")
    if "pci-0000_29_00.0" not in n or "analog" not in n or "iec958" in n:
        continue
    print(str(o["id"]) + "|" + n)
    break
')
	[ -n "$line" ] || return 0
	id=${line%%|*}
	name=${line#*|}
	wpctl set-default "$id" 2>/dev/null || true
	pw-metadata -n default 0 default.audio.sink "{\"name\":\"$name\"}" >/dev/null 2>&1 || true
	log "default sink -> $name"
}

set_cfg() {
	amixer -c "$CARD" sset 'Surround Channel Config' "$1" >/dev/null 2>&1 || return 1
	log "mixer -> $1"
}

get_out() {
	amixer -c "$CARD" sget 'AE-9 Output' 2>/dev/null |
		sed -n "s/.*Item0: '\(.*\)'/\1/p" | head -1
}

set_out() {
	amixer -c "$CARD" sset 'AE-9 Output' "$1" >/dev/null 2>&1 || return 1
	log "output -> $1"
}

# The analog sink node; wpctl set-route operates on the node, not the card.
sink_node() {
	pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Sink":
        continue
    n = p.get("node.name", "")
    if "pci-0000_29_00.0" not in n or "analog" not in n or "iec958" in n:
        continue
    print(o["id"]); break
'
}

# Route index currently assigned to the analog output of the device.
route_current() { # dev
	wpctl get-route "$1" 2>/dev/null |
		sed -n '/Audio\/Sink, node/{n;s/.*route \([0-9]*\).*/\1/p;q;}'
}

route_name() { # dev index
	pw-dump 2>/dev/null | python3 -c '
import json, sys
idx = int(sys.argv[1])
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Device":
        continue
    if p.get("device.product.id") != "0x0010":
        continue
    for e in ((o.get("info") or {}).get("params") or {}).get("EnumRoute") or []:
        if e.get("index") == idx:
            print(e.get("name", "")); sys.exit(0)
    break
' "$2"
}

route_index() { # name
	pw-dump 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for o in data:
    p = (o.get("info") or {}).get("props") or {}
    if p.get("media.class") != "Audio/Device":
        continue
    if p.get("device.product.id") != "0x0010":
        continue
    for e in ((o.get("info") or {}).get("params") or {}).get("EnumRoute") or []:
        if e.get("name") == name:
            print(e["index"]); sys.exit(0)
    break
' "$1"
}

set_route() { # index
	local s
	s=$(sink_node)
	[ -n "$s" ] || return 1
	wpctl set-route "$s" "$1" 2>/dev/null || return 1
	log "route -> $1"
}

route_for_out() {
	case "$1" in
		Headphone) route_index analog-output-headphones ;;
		Speakers)
			local idx
			idx=$(route_index analog-output-lineout)
			[ -n "$idx" ] || idx=$(route_index analog-output-speaker)
			echo "$idx"
			;;
	esac
}

# Wait for the card and for PipeWire to publish the AE-9.
for _ in $(seq 1 60); do
	[ -n "$(card_num)" ] && [ -n "$(dev_active)" ] && break
	sleep 1
done

last_cfg=""
last_prof=""
last_out=""
last_route=""
first=1
first_route=1
guard=0
rguard=0

while :; do
	sleep "$INTERVAL"
	read -r dev prof <<<"$(dev_active | tr '|' ' ')"
	[ -n "${dev:-}" ] || continue
	cfg=$(get_cfg)
	[ -n "$cfg" ] || continue
	pkey=$(cfg_for_profile "$prof")

	if [ "$first" = 1 ]; then
		# The saved ALSA control is the user's last choice; make the
		# desktop profile follow it at login.
		target=$(profile_for_cfg "$cfg")
		if [ -n "$target" ] && [ "$pkey" != "$cfg" ]; then
			set_profile "$dev" "$target" && pkey="$cfg"
			guard=$((SECONDS + 6))
		fi
		first=0
	elif [ "$SECONDS" -lt "$guard" ]; then
		: # an ACP profile switch takes a moment to settle
	elif [ "$cfg" != "$last_cfg" ]; then
		target=$(profile_for_cfg "$cfg")
		if [ -n "$target" ] && [ "$pkey" != "$cfg" ]; then
			set_profile "$dev" "$target" && pkey="$cfg"
			guard=$((SECONDS + 6))
		fi
	elif [ "$pkey" != "$last_prof" ] && [ -n "$pkey" ]; then
		set_cfg "$pkey" && cfg="$pkey"
		guard=$((SECONDS + 4))
	fi

	# The GNOME sound panel exposes the "Headphones" / "Line Out" routes of
	# the analog profile.  Keep them in step with the ACM relay.
	out=$(get_out)
	ridx=$(route_current "$dev")
	rname=""
	[ -n "$ridx" ] && rname=$(route_name "$dev" "$ridx")
	want=""
	case "$rname" in
		*headphones*) want="Headphone" ;;
		*lineout*|*speaker*) want="Speakers" ;;
	esac

	if [ "$first_route" = 1 ]; then
		idx=$(route_for_out "$out")
		[ -n "$idx" ] && set_route "$idx"
		first_route=0
		rguard=$((SECONDS + 3))
	elif [ "$SECONDS" -ge "$rguard" ] && [ "$rname" != "$last_route" ] &&
	     [ -n "$want" ] && [ "$want" != "$out" ]; then
		set_out "$want" && out="$want"
		rguard=$((SECONDS + 3))
	elif [ "$SECONDS" -ge "$rguard" ] && [ -n "$out" ] && [ "$out" != "$last_out" ]; then
		idx=$(route_for_out "$out")
		[ -n "$idx" ] && set_route "$idx"
		rguard=$((SECONDS + 3))
	fi

	last_cfg="$cfg"
	last_prof="$pkey"
	last_out="$out"
	last_route="$rname"
done
