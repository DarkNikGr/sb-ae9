#!/usr/bin/env bash
# Remove sb-ae9: DKMS modules (the in-tree ones take over after reboot), firmware, drop-ins, user service.
set -u; [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
usr="${SUDO_USER:-}"; home=$(getent passwd "$usr" | cut -d: -f6)
for v in $(dkms status 2>/dev/null | grep -oE 'sb-ae9[/,] *[0-9.]+' | grep -oE '[0-9.]+$' | sort -u); do dkms remove "sb-ae9/$v" --all; rm -rf "/usr/src/sb-ae9-$v"; done
rm -f /lib/firmware/ae9-dsp-output-overlay.bin /etc/modprobe.d/sb-ae9.conf /usr/local/libexec/sb-ae9/ae9-defaults.sh /usr/local/libexec/sb-ae9/ae9-resume.sh /usr/local/libexec/sb-ae9/ae9-unmute.sh /usr/lib/systemd/system-sleep/50-ae9-resume /etc/udev/rules.d/90-sb-ae9-name.rules
rm -f "$home/.config/wireplumber/main.lua.d/51-ae9-soft-mixer.lua" "$home/.config/wireplumber/wireplumber.conf.d/51-ae9-soft-mixer.conf" "$home/.config/wireplumber/main.lua.d/52-ae9-no-capture.lua" "$home/.config/wireplumber/wireplumber.conf.d/52-ae9-no-capture.conf" "$home/.config/pipewire/pipewire.conf.d/20-ae9-inputs.conf" "$home/.config/wireplumber/wireplumber.conf.d/30-ae9-names.conf" "$home/.config/systemd/user/ae9-defaults.service" "$home/.config/systemd/user/ae9-unmute.service" "$home/.local/bin/ae9-fx" "$home/.local/share/applications/ae9-fx.desktop"
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=sound 2>/dev/null || true
depmod -a; echo "removed; reboot to return to the in-tree driver (which does not support the AE-9)"
