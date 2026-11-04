#!/bin/bash
# Collect everything needed to read a bring-up report for a Creative CA0132 card
# (AE-9, AE-7, AE-5, Z-series) into one text file to attach to a GitHub issue.
# Read-only. No sudo needed for most of it; run with sudo for the full kernel log on
# distributions that restrict it. Contains no usernames, hostnames or network details.
set -u
OUT=${1:-ca0132-report-$(date +%Y%m%d-%H%M%S).txt}
codec=$(modinfo -n snd_hda_codec_ca0132 2>/dev/null)
core=$(modinfo -n snd_hda_core 2>/dev/null)
{
echo "== sb-ae9 report $(date -u +%FT%TZ) =="
echo "kernel: $(uname -r)   cmdline iommu: $(grep -oE 'iommu=[a-z]+|amd_iommu=[a-z]+|intel_iommu=[a-z]+' /proc/cmdline | tr '\n' ' ')"
echo "cmdline: $(cat /proc/cmdline 2>/dev/null)"
echo "dkms: $(dkms status 2>/dev/null | grep sb-ae9 | tr '\n' ';')"
echo "module: codec=$codec"
echo "        core=$core"
echo "sha256: codec=$([ -n "$codec" ] && sha256sum "$codec" 2>/dev/null | cut -c1-16)  core=$([ -n "$core" ] && sha256sum "$core" 2>/dev/null | cut -c1-16)"
echo "vermagic: codec=$(modinfo -F vermagic snd_hda_codec_ca0132 2>/dev/null) | core=$(modinfo -F vermagic snd_hda_core 2>/dev/null)"
echo "params: $(for p in /sys/module/snd_hda_codec_ca0132/parameters/*; do echo -n "$(basename $p)=$(cat $p) "; done 2>/dev/null)"
echo "firmware: $(ls -l /lib/firmware/ae9-dsp-output-overlay.bin 2>/dev/null | awk '{print $5" bytes"}')  sha256=$(sha256sum /lib/firmware/ae9-dsp-output-overlay.bin 2>/dev/null | cut -c1-16)"
echo; echo "== PCI =="; lspci -nn -d 1102: 2>/dev/null; for d in $(lspci -n -d 1102: | cut -d' ' -f1); do echo "0000:$d iommu_group=$(basename $(readlink /sys/bus/pci/devices/0000:$d/iommu_group 2>/dev/null) 2>/dev/null) type=$(cat /sys/bus/pci/devices/0000:$d/iommu_group/type 2>/dev/null)"; done
echo; echo "== ALSA cards =="; cat /proc/asound/cards
echo; echo "== codecs =="; for c in /proc/asound/card*/codec#*; do echo "$c: $(sed -n '1,2p' $c | tr '\n' ' ') subsystem=$(grep -m1 'Subsystem Id' $c | awk '{print $3}')"; done
echo; echo "== PCM status =="; for f in /proc/asound/card*/pcm*/sub*/status; do [ -r "$f" ] && echo "$f: $(tr '\n' ' ' < "$f")"; done
echo; echo "== kernel log: HDA/CA0132/AE lines (this boot) =="
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | grep -iE 'snd_hda|hdaudio|ca0132|AE-[579]|AMD-Vi|IO_PAGE|DMAR|azx' | sed -E 's/^(\[[^]]*\]) [^ ]+ kernel: /\1 /' | head -400
echo; echo "== AE-9 driver lines (last 120) =="
journalctl -k -b --no-pager -o short-monotonic 2>/dev/null | grep -E 'AE-9|ae9' | tail -120
echo; echo "== mixer (Creative card, simple controls) =="; amixer -c Creative scontents 2>/dev/null
echo; echo "== capture controls (raw) =="
amixer -c Creative contents 2>/dev/null | grep -A3 -E "name='(Capture|Mic Boost|What U Hear|Input Source|Digital Capture|IEC958 Capture)" | head -120
echo; echo "== ae9-fx --selftest =="
if command -v ae9-fx >/dev/null 2>&1; then
	ae9-fx --selftest 2>&1 | head -80
elif [ -x tools/ae9-fx ]; then
	python3 tools/ae9-fx --selftest 2>&1 | head -80
else
	echo "ae9-fx not installed"
fi
echo; echo "== PipeWire =="; wpctl status 2>/dev/null | sed -n '/^Audio/,/^Video/p' | grep -vE '^ │\s*$'
echo; echo "== session units =="
systemctl --user cat ae9-defaults.service ae9-unmute.service 2>/dev/null
echo "states: defaults=$(systemctl --user is-active ae9-defaults.service 2>/dev/null) unmute=$(systemctl --user is-active ae9-unmute.service 2>/dev/null)"
echo; echo "== session logs =="
journalctl --user -u ae9-defaults -u ae9-unmute -b --no-pager -o cat 2>/dev/null | tail -30
} > "$OUT" 2>&1
echo "written: $OUT ($(wc -l < "$OUT") lines). Review it, then attach it to the issue."
