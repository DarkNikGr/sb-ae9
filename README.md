# Sound Blaster AE-9 — Linux driver

[![ci](https://github.com/DarkNikGr/sb-ae9/actions/workflows/ci.yml/badge.svg)](https://github.com/DarkNikGr/sb-ae9/actions/workflows/ci.yml)

Out-of-tree ALSA driver for the **Creative Sound Blaster AE-9** (PCI `1102:0010`,
subsystem `1102:0071`): dual CA0132 “Sound Core3D” HDA codecs, an ES9038Q2M headphone
DAC, a SABRE9006 line-out DAC, and the external **Audio Control Module** (ACM) with its
volume knob, dB display and buttons.

The driver is based on the kernel's `snd-hda-codec-ca0132` and adds the AE-9 bring-up,
the ACM protocol and routing. A small HDA-core fix stops this card from hard-locking
the machine. Everything runs under plain ALSA, PipeWire and WirePlumber.

**Status: working.** Developed and tested on the physical card and ACM on Fedora 44
(kernel 7.2) and Ubuntu (kernel 7.0). Not upstream yet.

---

## Hardware

What the card and its Audio Control Module (ACM) physically provide. The status uses
the same meaning as the Features table below.

| Block | Detail | Status |
|---|---|---|
| PCI | `1102:0010`, subsystem `1102:0071` (PCIe) | Working |
| Codecs | 2× CA0132 Sound Core3D (main + secondary) | Working |
| Headphone DAC | ES9038Q2M (`0x48`) | Working |
| Line-out DAC | SABRE9006 (`0x49`) | Working; drives rear and center/sub |
| ACM | Volume knob, dB display, mute, SBX button/light, output toggle | Working |
| ACM gain | 3-position IEM / N / HIGH switch (analog stage) | Hardware switch; no software control |
| Headphone amp | 16–600 Ω supported, 1 Ω output impedance | Working |
| Analog out | Headphone 6.35 mm (ACM), front L/R, rear, center/sub | Working; 5.1 on jacks 13–16 |
| Analog in | ACM 6.3 mm mic, XLR mic, rear line-in | Working |
| XLR 48 V | Phantom power via the ACM button | Not exposed in software |
| Optical | S/PDIF in and out | Working, 44.1–192 kHz |
| Rates | 44.1 / 48 / 88.2 / 96 / 192 kHz | Working; **192 kHz maximum** |
| DSP | SBX, Crystalizer, Dialog Plus, Smart Volume, X-Bass, Surround, EQ | Working |
| Mic DSP | CrystalVoice, VoiceFX, Mic SVM, Noise Reduction | Working |
| Loopback | What U Hear | Working |

---

## Features

| Area | Feature | Status |
|---|---|---|
| ACM | Headphone output (ES9038Q2M) | Working |
| ACM | Volume knob and dB display, 1 dB steps (−90 … 0 dB) | Working |
| ACM | Mute (short press, `MUTE` on the display) | Working |
| ACM | Output toggle (hold 1.5–3 s, `-HP-` / `-SP-`) | Working; exclusive by default (`ae9_out_mute=1`) |
| ACM | SBX button and light | Working |
| ACM | Headphone gain (IEM / Normal / High) | Hardware 3-position switch; not software-controlled |
| ACM | Mic / line input (6.3 mm, XLR) | Working; 48 V phantom not exposed |
| Card | Playback 44.1 / 48 / 88.2 / 96 / 192 kHz | Working (native rate with Direct Mode) |
| Card | SBX effects, per-effect switches and levels | Working |
| Card | 5.1 analog output on jacks 13–16 (front, rear, center/sub) | Working; rear enabled through codec pin `0x11` |
| Card | Speaker layout ↔ PipeWire profile (`2.0`…`5.1`) | Working, both directions (`ae9-profile-sync`) |
| Card | GNOME “Headphones” / “Line Out” ↔ ACM output | Working, both directions (`ae9-profile-sync`) |
| Card | Rear line-in / mic-in | Working (capture device 4) |
| Card | What U Hear loopback | Working (capture device 2) |
| Card | Optical S/PDIF out | Working, 44.1–192 kHz (loopback-tested) |
| Card | Optical S/PDIF in | Working, 44.1–192 kHz (loopback-tested) |
| Card | Mic effects (CrystalVoice) | Working |
| Card | Suspend / resume | Working, with the installed unmute hook |
| Card | Direct Mode (follow the stream rate) | Working 44.1–192 kHz, opt-in |

**Not supported:** 48 V phantom power, AC3/DTS passthrough, and importing a Windows
SBX profile. The IEM/Normal/High headphone gain is handled by the 3-position switch on
the ACM; the driver keeps the ES9038Q2M trims at 0 dB (as Windows does) and exposes no
duplicate software control. 384 kHz was tested and rejected (the HDA link does not
carry the 8× rate). **192 kHz is the maximum.**

---

## Roadmap

Open work, in rough order. Checked items are already in this tree and tested on the
card; they are kept here so the scope is visible.

- [x] **Analog IEM / Normal / High gain** — the 3-position switch on the ACM owns the
      gain. The driver leaves the ES9038Q2M trims at 0 dB and exposes no duplicate
      software control; nothing is left to implement in software.
- [x] **Headphone / line-out routing** — shared `Headphone+LO`, auto-detect, exclusive
      output switching and the ES9038/SABRE mutes.
- [x] **Analog 5.1** — front, rear and center/sub on jacks 13–16; rear line-out is codec
      pin `0x11`, balanced against the front pair, and muted with the headphones.
- [x] **Desktop sync** — `Surround Channel Config` ↔ PipeWire profile, and the GNOME
      Headphones/Line Out routes ↔ the ACM `AE-9 Output` relay.
- [x] **Direct Mode** — stream-rate following at 44.1–192 kHz, effects off, stereo.
- [x] **Optical S/PDIF** — playback and capture at 44.1–192 kHz, loopback-tested.
- [x] **Desktop entry** — `install.sh` installs `ae9-fx` and its application-grid entry.
- [ ] **Upstream** — send the 24-patch series and address review.
- [ ] **Packaging** — RPM/COPR for Fedora.
- [ ] **Packaging** — DEB and AUR.
- [ ] **Release** — tag `v0.1.0` and publish a tarball.
- [ ] **`ae9ctl`** — profiles (headphones / speakers / recording) and save/restore.
- [ ] **Docs** — man page for `ae9-fx` and `ae9ctl`.
- [ ] **CI** — kernel-version matrix and a saved hardware selftest report.
- [ ] **Driver** — AC3/DTS passthrough over optical S/PDIF (blocked: there is no
      IEC958 subframe route on device 10).
- [ ] **Driver** — import SBX profiles from the Windows package.
- [ ] **Driver** — document the remaining ACM/DSP registers.

---

## Read this before installing

1. **Never load an unpatched HDA core against this card.** The stock kernel's HDA core
   can hard-lock the machine when it probes the AE-9 (posted-write bug, `patches/0001`).
   This package installs the fixed core as an override. Do not remove it while the card
   is installed unless you blacklist `snd_hda_intel` for it.
2. **AMD IOMMU requires `iommu=pt`.** Without it, buffer wraps become aborted DMA reads
   (`AMD-Vi: IO_PAGE_FAULT`), which crackle and eventually stall the DSP. Add
   `iommu=pt` to `GRUB_CMDLINE_LINUX_DEFAULT`, run `update-grub`, reboot.
   VFIO passthrough keeps working.
3. **The ACM can hang.** A warm reboot does not clear it: power the PC fully off, wait
   30 s, reseat the ACM cable, cold boot.
4. **Main-codec capture is dangerous without `ae9_mic=1`.** Opening the main codec's
   capture hard-locked the machine in testing. The shipped `install/sb-ae9.conf` sets
   `ae9_capture=1 ae9_mic=1`. Leave it that way.
5. **Do not run `tools/acm-tool` while the driver's ACM service is running** (UART
   collision). Never run its `acm=1/2` bring-up on a live card: the GPIO pulse resets
   both DACs. `acm=3` is the UART-only mode.

---

## Requirements

- Linux **6.17 or newer**, with headers for the running kernel.
- `dkms`, `gcc`, `make`, `python3`, `curl`.
- PipeWire + WirePlumber for the desktop integration.
- Secure Boot: DKMS signs the modules with its own key. Enrol it once
  (`mokutil --import /var/lib/dkms/mok.pub`, reboot, enrol) or use your
  distribution's DKMS signing setup.
- Creative's Windows driver package for the DSP firmware segment (next section).

---

## Firmware

Two pieces are needed:

1. **Base DSP image** `ctefx-desktop.bin`. Debian/Ubuntu ship it in `linux-firmware`;
   on Fedora install `alsa-firmware` (it provides `ctefx-desktop.bin`, `ctefx.bin` and
   `ctefx-r3di.bin`).
2. **Output-connect overlay** — a 432-byte program patch that only exists inside
   Creative's `CtxHda.sys`. It is Creative's code and is not redistributed here.
   `tools/ae9-firmware-extract.sh` carves it from the installer you are licensed to
   use, verifies its SHA-256 and writes `/lib/firmware/ae9-dsp-output-overlay.bin`.

Get **Sound Blaster Command** for the AE-9 (`AECMDMasterInstaller_3.4.92.00.exe`,
~138 MB) from Creative's download page:

- <https://support.creative.com/downloads/download.aspx?nDownloadId=100330>
- If that link changes: <https://support.creative.com/Downloads/searchdownloads.aspx?filename=SB#>
  (search “AE-9”, package “Sound Blaster Command”). The page has a licence click and a
  captcha, so the download itself is manual. Nothing from it is executed.

The extractor unpacks the Inno Setup layers with `innoextract` (fetched automatically
if missing). A mounted Windows partition or a bare `CtxHda.sys` also works
(`--windows DIR`, `--sys FILE`).

> On the Fedora/alsa-firmware card the base image alone already connects the DSP
> output, so playback works even when the overlay is missing (the driver still logs
> the missing file). Install the overlay anyway; it is required on other cards.

---

## Install

```sh
git clone https://github.com/DarkNikGr/sb-ae9
cd sb-ae9
sudo ./install.sh --exe ~/Downloads/AECMDMasterInstaller_3.4.92.00.exe
```

On AMD systems with the IOMMU enabled, add `iommu=pt` before rebooting.

`install.sh`:

- builds and installs the `sb-ae9` DKMS module set for the running kernel;
- extracts and installs the firmware overlay (`--no-firmware` skips this if it is
  already in place);
- installs `/etc/modprobe.d/sb-ae9.conf`;
- installs PipeWire source/name rules, the WirePlumber name rule and the udev card
  name rule; an existing `20-ae9-inputs.conf` is kept, because it also carries the
  per-input format choices from the GUI (use `AE9_RESET_CONFIGS=1` to replace it);
- installs the session-defaults user service, the post-PipeWire unmute unit and the
  post-resume system-sleep hook;
- warns about Secure Boot and a missing `iommu=pt`.

After the reboot the card comes up by itself.

**Uninstall:** `sudo ./uninstall.sh`. The in-tree driver returns after a reboot, but it
does not support the AE-9.

---

## Verify

```sh
dmesg | grep 'AE-9'
```

A healthy boot shows `converter bring-up done` and
`AE-9 ACM: present, firmware …, output headphone`, followed a few seconds later by
`AE-9 ACM: regs …`.

```sh
wpctl status                    # the AE-9 analog sink should be the starred default
amixer -c Creative sget Master
amixer -c Creative sget 'AE-9 Output'
amixer -c Creative sget 'Enable OutFX'
```

The card's ALSA id is `Creative`; the numeric index can change between boots, so always
address it by id.

The user service `ae9-defaults` selects the ACM headphones, sets a safe Master level
and makes the AE-9 analog sink PipeWire's default.

### One-command health check

`tools/ae9-selftest.sh` runs the whole matrix and prints one summary: module,
bring-up log, mixer controls, PipeWire nodes and defaults, capture/playback at
44.1/96/192 kHz, and the optical S/PDIF loopback.

```sh
tools/ae9-selftest.sh                 # full run (plays a short 1 kHz tone)
tools/ae9-selftest.sh --quick         # 48 kHz only
tools/ae9-selftest.sh --no-playback --no-loopback
tools/ae9-selftest.sh --json ae9.json --report ae9.log
```

It temporarily sets the PipeWire graph rate for each step and restores the previous
`clock.force-rate` on exit, including on Ctrl-C. Exit status is `0` when every check
passed; warnings (for example the card is not the default sink) and skips do not fail
the run. Attach the JSON file to a bug report.

---

## Using the card

### Volume and mute

- The ACM knob, or `amixer -c Creative sset Master <0-90>`.
  Steps are 1 dB: **90 = 0 dB**, 72 ≈ −18 dB, 65 ≈ −25 dB.
- PipeWire's slider drives the same hardware `Master`, so the knob and the desktop
  slider are one control.
- Mute: short knob press, or `amixer -c Creative sset Master toggle`. The display
  shows `MUTE`.
- `ae9-defaults` sets Master to 65 at every login. Override it with
  `systemctl --user edit ae9-defaults` and:
  ```ini
  [Service]
  Environment=AE9_LEVEL=72
  # Environment=AE9_OUT=Speakers
  ```

### Output selection

```sh
amixer -c Creative sset 'AE-9 Output' Headphone
amixer -c Creative sset 'AE-9 Output' Speakers
```

Or hold the knob for 1.5–3 s. With the default `ae9_out_mute=1` the two positions are
exclusive: Headphone writes the ES9038 front mute (register `0x1d`), mutes the
SABRE9006 and disables every line-out pin, so jacks 13–16 are silent; Speakers keeps
the line-out live and drops the ACM headphone-amp bit.

Set `ae9_out_mute=0` in `/etc/modprobe.d/sb-ae9.conf` if you want both outputs audible
at the same time. The exclusivity is a driver choice, not a hardware limit.

The `ae9-profile-sync` user service bridges the two layers the desktop exposes:

- `Surround Channel Config` (`2.0`, `2.1`, `4.0`, `4.1`, `5.1`) ↔ the PipeWire card
  profile and default sink.
- GNOME's **Headphones** / **Line Out** routes ↔ this `AE-9 Output` relay, so changing
  either one updates the other. The same service makes the analog 5.1 sink the default
  instead of the optical S/PDIF.
- The volume is mirrored across the switch: WirePlumber stores a separate level for
  each port, so without this the card would jump between the last headphone level and
  the last line-out level. The service re-applies the previous level after every route
  change, whichever side started it.

- The control is deliberately **not** called “Output Select”: desktop ALSA profiles
  map that name onto sink ports and rewrite it on every route restore.
- Headphone gain: use the 3-position **IEM / N / HIGH** switch on the ACM. It selects
  the analog gain stage and is not visible to the host, so there is no ALSA control
  for it. The driver keeps the ES9038Q2M trims at 0 dB; use Master (or the knob) for
  level. On an AE-5/AE-7 the equivalent control is still `AE-5: Headphone Gain`
  because those cards implement it digitally. Upgrading from a build that exposed
  the old AE-9 control makes the first `alsactl restore` warn about the removed
  control; `sudo alsactl store` once drops the stale entry.
- `HP/Speaker Auto Detect` makes the output follow the **ACM 3.5 mm jack**. The ACM
  firmware does not report the 6.35 mm jack, so switch that one by hand.

### Capture

| Source | ALSA device | Notes |
|---|---|---|
| ACM microphone (main codec) | `hw:Creative,0` | Default PipeWire source |
| What U Hear (DSP loopback) | `hw:Creative,2` | Records what the card plays; ≤ 96 kHz |
| Rear line-in (secondary codec) | `hw:Creative,4` | ≤ 192 kHz |
| Optical S/PDIF in | `hw:Creative,10` | ≤ 192 kHz; needs the capture switch on |

```sh
arecord -D hw:Creative,0  -f S32_LE -r 48000 -c 2 -d 5 mic.wav
arecord -D hw:Creative,4  -f S32_LE -r 48000 -c 2 -d 5 line.wav
arecord -D hw:Creative,2  -f S32_LE -r 48000 -c 2 -d 5 loop.wav
```

Under PipeWire the ACM mic is the default source. The card's nodes are named
**“Sound Blaster AE-9 Output”** and **“Sound Blaster AE-9 Microphone”**. The installer
also exposes:

- **“Sound Blaster AE-9 Line In”** — `hw:Creative,4`;
- **“Sound Blaster AE-9 What U Hear”** — `hw:Creative,2`;
- **“Sound Blaster AE-9 S/PDIF”** — `hw:Creative,10`;
- **“Sound Blaster AE-9 Optical S/PDIF”** — playback sink on `hw:Creative,10`.

By default the extra sources follow the PipeWire graph. The GUI's **Capture** page has
a separate rate and bit-depth setting for each input:

| Input | Node | Rates | Storage |
|---|---|---|---|
| Microphone (device 0) | `alsa_input.pci-0000_29_00.0.analog-stereo` | 44.1–96 kHz | `54-ae9-input-format.conf` |
| Line In (device 4) | `alsa_input.ae9_linein` | 44.1–192 kHz | `20-ae9-inputs.conf` |
| What U Hear (device 2) | `alsa_input.ae9_wuh` | 44.1–96 kHz | `20-ae9-inputs.conf` |
| S/PDIF in (device 10) | `alsa_input.ae9_spdif` | 44.1–192 kHz | `20-ae9-inputs.conf` |

The optical output is a separate PCM as well, with its own rate and bit-depth rows on
the **Output** page (under *S/PDIF (optical)*). The analog format from the Format page
does not apply to it; this setting is stored for `alsa_output.ae9_spdif` in
`20-ae9-inputs.conf`. **Auto** follows the graph rate, a fixed value opens that PCM at
the selected rate and the graph resamples into it.

Choose **Auto** to leave the ALSA default (`S32LE`, graph rate). A forced rate is that
input's own rate, but PipeWire still has one graph clock: while playing, the output and
the capture input may be resampled to the graph rate. If you need a capture-only session
at another rate (for example 96 kHz with nothing playing), use the GUI's **Force rate**
on the Format page.

The microphone and the rear line-in are separate PCM devices. The **Input Source**
control only switches the main codec's ADC (Microphone / Line In); it does not change the
rear line-in, which is the secondary codec's own capture device and is selected as
**Sound Blaster AE-9 Line In** in the recording application.

Capture level and mic boost are the card's hardware amp (1 dB steps, 90 = 0 dB): use
`Capture` in `amixer` or the **Capture** page of the GUI, plus `Mic Boost`
(0/10/20/30 dB). PipeWire/GNOME add their own software source volume on top. The rear
line-in has no hardware amp of its own, so its level is the source volume in the
desktop.

> In Audacity/OBS prefer the explicit AE-9 source over the generic `default` entry,
> which can advertise a bogus 128-channel maximum. Set 1 or 2 recording channels.

### Optical S/PDIF

Both directions are tested at 44.1 / 48 / 88.2 / 96 / 192 kHz with an optical loopback
cable (out → in). An 8 s run at 192 kHz was clean, and the received channel status
matches the transmitter.

For playback pick the **“Sound Blaster AE-9 Optical S/PDIF”** sink. The card's ACP
digital profile uses PCM device 1, which is **not** wired to the optical port on this
card: selecting that profile shows **“Sound Blaster AE-9 S/PDIF (internal)”**, which is
silent at the optical port, and hides the analog sink. `ae9-defaults` restores the
analog profile at login.

The S/PDIF input is silent until the optical input switch is on. `ae9-defaults` turns
it on at login, and the GUI's Output page has the same switch.

**The optical link is stereo PCM.** 5.1 is available on the analog line-out, not over
S/PDIF. AC3/DTS passthrough is not implemented: the optical PCM is plain S16/S32 and
does not expose IEC958 subframes, so the ALSA `a52` encoder path cannot drive it.
(Tested; `alsa-plugins-a52` was installed and removed again.)

#### Loopback self-test

```sh
tools/spdif-loopback-test.sh          # PipeWire adapters, all rates
tools/spdif-loopback-test.sh --quick  # 48 kHz only
tools/spdif-loopback-test.sh --raw    # raw ALSA (needs the hw device free)
```

The default path uses the PipeWire adapter nodes, which is what the desktop uses.
The adapters follow the stream rate, so the link runs natively at each rate. `--raw`
drives the ALSA devices directly and only works while PipeWire is not holding
`hw:Creative,10`. The script turns both S/PDIF switches on, plays a 1 kHz tone, reports
level, frequency and dropouts, then restores the switches. The DSP is in the path in
both directions, so this checks the link and the rates, not bit-exactness.

### Effects (SBX)

Master switch: the SBX button, or
`amixer -c Creative sset 'Enable OutFX' on|off`. The button light follows the real
state. It is **off at every login** so the clean path is the default.

The per-effect controls only act while the master switch is on. With it off the driver
forces every output processor off in the DSP; the individual switches remember what to
re-enable. Switching the master on enables the processors at Creative's stock levels:

| Processor | What it does | Stock | Notes |
|---|---|---|---|
| `FX: Crystalizer` | Sharper attacks, brighter top, more punch | on, 65 | |
| `FX: Dialog Plus` | Lifts the vocal / dialogue midrange | on, 50 | |
| `FX: Smart Volume` | Loudness leveler | on, 74 | Can make volume “pump”; `FX: Smart Volume Setting`: Normal / Loud / Night |
| `FX: X-Bass` | Bass enhancement | on, 50 | Crossover `FX: X-Bass Crossover` 1–100, default 8 (≈ 80 Hz) |
| `FX: Surround` | Virtual surround / stereo widening | off, 67 | Keep `Surround Channel Config` at 2.0 for headphones |
| `FX: Equalizer` | 10-band EQ by preset | on, Flat | Presets: Flat, Acoustic, Classical, Country, Dance, Jazz, New Age, Pop, Rock, Vocal |

Examples:

```sh
amixer -c Creative sset 'FX: Smart Volume' off     # stop the level pumping
amixer -c Creative sset 'FX: X-Bass' 20
amixer -c Creative sset 'FX: Crystalizer' 30
amixer -c Creative sset 'FX: Equalizer Preset' Rock
```

If a change does not seem to take, pause playback for a few seconds and resume: some DSP
settings are picked up at stream start.

Capture-side processors (`Enable InFX`, `FX: Voice Focus`, `FX: Noise Reduction`,
`FX: Mic SVM`, `VoiceFX`) run only while a capture stream is active. They use
Creative's stock levels; there is no SBX profile import.

### Direct Mode and rates

The analog PCM advertises up to 192 kHz. With Direct Mode off the DSP still resamples
the stream to its internal rate. Direct Mode makes the DSP/I2S chain follow the
playback stream's rate:

```sh
# /etc/modprobe.d/sb-ae9.conf
options snd-hda-codec-ca0132 ae9_direct=1
```

or toggle `AE-9 Direct Mode` in the mixer / GUI. A change takes effect at the next
stream start. Direct Mode also switches the SBX/OutFX and InFX masters off and
constrains the analog PCM to stereo, like Windows' Direct Mode. The DSP stays in the
path, so bit-exactness is not proven end to end. `ae9-defaults` turns it off at
every login, so a manual enable lasts for the session; the module default is
also `0`.

For a fully native chain:

```sh
aplay -D hw:Creative,0 -f S32_LE -r 96000 -c 2 file.wav   # bypasses PipeWire
```

Through PipeWire the graph rate applies to all streams. Manage it on the GUI's
**Format** page (`default.clock.allowed-rates`, **Force rate**) or with
`pw-metadata`. The GUI's **Hardware rate** row shows what the card is actually
running, and reports **“held at N Hz (no active stream)”** when an idle player or a
level meter keeps the device open without playing.

---

## GUI: `ae9-fx`

A GTK 4 / libadwaita control panel that drives the same ALSA controls as `amixer`.
No root needed.

| Page | What it controls |
|---|---|
| **Volume** | Master, mute, ACM selector status |
| **Output** | `AE-9 Output`, auto-detect, surround, S/PDIF out/in switches, separate S/PDIF rate/bits |
| **Format** | Running format, graph clock, allowed and forced rates, Direct Mode, sample bits, PipeWire restart |
| **SBX** | Effects master, each processor and level, 10-band EQ |
| **DAC** | Oversampling filter (headphone gain is the ACM switch) |
| **Capture** | Separate microphone, line-in, What U Hear and S/PDIF groups, per-input rate/bits, capture level/switch, mic boost, CrystalVoice and VoiceFX |

The header has **reload** (re-read the card) and **reset** (manufacturer defaults:
Master 65, Headphone output, effects off). The Format page, `AE-9 Output` and
`Surround Channel Config` refresh every 2 s, so changes made with the ACM knob or
from GNOME appear in the window without a manual reload.

Dependencies (Fedora): `python3-gobject gtk4 libadwaita`.

`sudo ./install.sh` installs `ae9-fx` to `~/.local/bin/ae9-fx` and the
application-grid entry to `~/.local/share/applications/ae9-fx.desktop`, so the
installed copy always matches the driver. For a manual install:

```sh
install -Dm755 tools/ae9-fx ~/.local/bin/ae9-fx
ae9-fx
```

`ae9-fx --selftest` prints every control it reads without opening a window — the
quickest way to tell a GUI bug from a driver state.

---

## PipeWire / WirePlumber integration

- The card's ACP profile provides the analog sink and microphone. `30-ae9-names.conf`
  gives them the friendly names above; `90-sb-ae9-name.rules` makes udev report the
  card as **“Sound Blaster AE-9”** instead of the chipset string.
- `20-ae9-inputs.conf` adds the extra capture sources and the optical sink as adapter
  nodes on the raw PCM devices. They are intentionally plain adapters: explicit names,
  stable behaviour across profile switches, and no dependence on the ALSA profile set.
- WirePlumber drives the hardware mixer (`soft-mixer=false`, the default) through the
  shared **`Headphone+LO`** control, which sets both the ACM headphones and the rear
  line-out. `Master` and the knob are the same 1 dB hardware control.
- All analog profiles (`analog-stereo`, `analog-surround-21/40/41/50/51`) stay
  available: the driver marks the permanently wired line-out pins as
  `NO_PRESENCE`, so ACP sees a phantom jack instead of an unplugged one. The 5.1
  profile therefore no longer collapses back to stereo (or to S/PDIF) when playback
  stops.
- `ae9-profile-sync` keeps the ALSA speaker layout, the PipeWire profile and the
  GNOME Headphones/Line Out routes in sync; see *Output selection* above.

The installer does not use a custom ALSA profile set. That keeps the stock ACP
profiles available; the price is that the extra PCM devices must be exposed by
`20-ae9-inputs.conf`.

---

## Session services and defaults

`ae9-defaults` (user service, oneshot) runs at login and:

- waits for the AE-9 and selects its analog profile if WirePlumber did not;
- selects `AE-9 Output` = Headphone, turns effects off and leaves Direct Mode off;
- sets PCM / `Headphone+LO` / Surround to 100 % and Master to `AE9_LEVEL` (default 65);
- turns on the optical S/PDIF playback and capture switches;
- makes the AE-9 analog sink PipeWire's default and pins the configured default
  sink/source;
- restores the analog microphone as the default source if a profile change left an
  extra AE-9 source in that role;
- re-checks routing/level once after a late route restore.

```sh
systemctl --user restart --no-block ae9-defaults
journalctl --user -u ae9-defaults
```

`ae9-profile-sync` (user service, always running) keeps two pairs of controls in
step, polling every 2 s:

- `Surround Channel Config` (`2.0`…`5.1`) ↔ the PipeWire card profile and the analog
  sink used as default;
- the GNOME **Headphones** / **Line Out** route ↔ the `AE-9 Output` relay (the same
  control the ACM knob and `ae9-fx` write).

It also keeps the volume constant when the output switches. WirePlumber remembers a
separate volume for every route; the service saves the level before a route change and
re-applies it afterwards, so the ACM knob, `ae9-fx` and the GNOME panel all keep the
same loudness.

It also names every analog sink (`Sound Blaster AE-9 Output`, `… 2.1`, `… 4.0`,
`… 4.1`, `… 5.0`, `… 5.1`) and gives it priority over the optical S/PDIF.

```sh
systemctl --user restart ae9-profile-sync
journalctl --user -u ae9-profile-sync
```

`ae9-unmute.service` (user unit, `WantedBy=pipewire.service`) re-asserts the
`Headphone+LO` switch after PipeWire/WirePlumber starts, because a route restore can
leave it off while the sink still looks unmuted.

`50-ae9-resume` (system-sleep hook) schedules the same unmute after resume, once
WirePlumber's route restore has settled.

---

## Module parameters

Set in `/etc/modprobe.d/sb-ae9.conf`:

| Parameter | Default | Meaning |
|---|---|---|
| `ae9_acm_poll` | `1` | Live ACM service: knob, display, buttons, keepalive. `0` initialises the module once and stays quiet (diagnostic baseline). |
| `ae9_capture` | `0` | Expose the main codec's capture streams. The shipped config sets `1`. |
| `ae9_mic` | `0` | Initialise the DSP microphone path. Required with `ae9_capture=1`; without it, opening main-codec capture can hard-lock. The shipped config sets `1`. |
| `ae9_out_mute` | `1` | Mute the unselected output (ES9038 front mute) when switching headphone/line-out. `0` restores “both can be audible”. |
| `ae9_direct` | `0` | Follow the stream rate on the DSP/I2S path (Direct Mode). Also exposed as `AE-9 Direct Mode`. |

The secondary codec's standard ADC (rear line-in and S/PDIF in) is always exposed.

---

## Troubleshooting

### No sound although everything looks right

Check the DSP overlay readback:

```sh
journalctl -k -b | grep -E 'overlay (readback|load failed)'
```

- `overlay readback 0x3f3b4=04000086` is a good boot.
- `00000000` plus `loader-mode overlay load failed` means the output-connect patch did
  not load: the DSP runs but is not wired to the DACs. This can persist across reboots
  because the slot stays on standby power.

**Remedy:** shut down, switch the PSU off (or pull the plug), press the power button
once to drain, wait 30 s, power on.

### Silent after a PipeWire / WirePlumber restart

A route restore can leave `Headphone+LO Playback Switch` off while the sink reports a
normal unmuted volume. Check and fix:

```sh
amixer -c Creative sget 'Headphone+LO'
amixer -c Creative sset 'Headphone+LO' on
```

The installed `ae9-unmute.service` does this automatically for a few seconds after the
graph starts. If the knob also drove Master down, raise it:
`amixer -c Creative cset numid=14 90`.

### Silent after suspend/resume

WirePlumber's route restore can mute `Headphone+LO` (and sometimes `Surround`). The
`50-ae9-resume` hook unmutes them about 20 s after resume; check
`journalctl -b | grep ae9-resume`. By hand:

```sh
amixer -c Creative sset 'Headphone+LO' on
amixer -c Creative sset Surround unmute
```

### Crackle, dropouts, or a stalled DSP stream

Check the kernel log for `AMD-Vi: IO_PAGE_FAULT`. If present, `iommu=pt` is missing
from the kernel command line. Add it and reboot.

### The ACM is dead

Power the machine fully off (not a warm reboot), wait 30 s, reseat the ACM cable, then
cold boot.

### The rear or center/sub jacks are silent

Check, in this order:

1. `AE-9 Output` is **Speakers** — Headphone mutes every line-out by design.
2. `Surround Channel Config` and the PipeWire profile are the same (`5.1` for all six
   channels); `ae9-profile-sync` keeps them in step.
3. `Surround`, `Center` and `LFE` playback switches are on and their volumes are up.
4. The card is on a driver that includes the pin `0x11` rear-line-out fix; the old
   AE-5/AE-7 mapping used to disable that pin in speaker mode.

If the jacks are still silent, attach `tools/collect-report.sh` output and the size
and SHA-256 of your `ctefx-desktop.bin` to an issue.

---

## Diagnostics and bug reports

`tools/collect-report.sh` writes one read-only text file with the HDA/CA0132 kernel
lines, codec ids, module and firmware state, PCI/IOMMU state, mixer, PCM status, the
GUI selftest and hashes. It contains no usernames, hostnames or network details.
Attach it to a GitHub issue.

`tools/acm-tool` is a throw-away kernel module that maps the card's BAR2 and talks to
the ACM UART, the GPIO block and the DAC I2C command engine. Park the driver's ACM
service first (`echo 0 | sudo tee /sys/module/snd_hda_codec_ca0132/parameters/ae9_acm_poll`)
and read Hazard 5.

| Mode | Purpose |
|---|---|
| `acm=3` | UART-only bring-up, safe on a live card |
| `acmget=<reg>` | Read an ACM register |
| `acmdump=1` | Read ACM registers 0–31 once |
| `acmwatch=<seconds>` | Poll registers 0–7 and log every change |
| `acmset=<reg>,<value>,<mask>` | Write ACM bits |
| `acmtext=<text>` | Write the display |
| `raw=f0,22,02,01,00,f7` | Send one frame and print the reply |
| `i2cdump=0x48` / `0x49` | Dump the ES9038Q2M / SABRE9006 DAC |
| `i2c=<group>,<reg>,<val>` | DAC register write |
| `acm=1` / `acm=2` | Full Windows-style bring-up, including the DAC-resetting GPIO pulse; only without the driver loaded |

---

## Repository layout

```
driver/ca0132/      codec driver (kernel ca0132.c + AE-9 support)
driver/hda-core/    kernel HDA core + the posted-write fix, built as an override
patches/            upstream series against sound.git for-next (see patches/README.md)
tools/              ae9-fx GUI, selftest, firmware extractor, report collector,
                    S/PDIF loopback test, acm-tool
install/            modprobe options, PipeWire sources, WirePlumber names,
                    udev name rule, session defaults, GUI desktop entry,
                    unmute/resume hooks
.github/            CI: checkpatch, patch application, lint and module builds
docs/               investigation log, protocol notes, register captures
```

## Upstream status

`patches/` is the upstream-shaped series against the current sound.git
`for-next` branch.  The HDA-core fix is generic; the codec support is split
into 24 feature patches in `patches/series/` (plus a cover letter).  All
patches pass `checkpatch.pl` and the series applies to a clean `for-next`
tree and builds against the 7.2 headers.  The out-of-tree tree keeps a
scoped version of the core readback because its DKMS module replaces
`snd-hda-core` for every controller.  See `patches/README.md`.

The analog 5.1 output, the pin `0x11` rear fix and the desktop sync services
are newer than the current 24-patch series; folding them into the series is
the next upstream step.

---

## What the driver adds

For readers of `patches/` and `driver/ca0132/ca0132.c` (`QUIRK_AE9`):

- Windows-style bring-up replayed from the vendor driver: DSP master-control sequence,
  ASI/PLL and DAC configuration over the BAR2 command engine, the 8051 router hooks,
  and the output-connect overlay loaded via
  `request_firmware("ae9-dsp-output-overlay.bin")`.
- The ACM protocol over the 16550 in BAR2 (115200 baud, sysex-style frames): presence
  probe, keepalive, register access, display text, SBX light, button/knob polling.
  Power-up writes GPIO pin 5 only; the Windows pin-0 pulse is never issued because it
  resets both DACs.
- Volume: 1 dB DAC steps with 0 dB at the top (step 90), shared by the knob, `Master`
  and `Headphone+LO`. The DSP volume stage is parked at 0 dB at bring-up.
- Controls: `AE-9 Output` (renamed so desktop profiles cannot rewrite it), the SBX
  master defaulting off, the output auto-detect gate and the Direct Mode switch.
- Analog 5.1: three output pairs through the DSP, with the rear line-out on codec pin
  `0x11` (the pin the AE-5/AE-7 use for the rear headphone jack), the DSP output
  trims balanced at 0 dB and the SABRE9006 muted with the headphones.
- Desktop: the headphone and line-out pins are marked “no presence detect”, giving
  ALSA phantom jacks so every analog profile (stereo, 2.1, 4.0, 4.1, 5.0, 5.1) stays
  available and WirePlumber can default to the active one instead of S/PDIF.
- Robustness: codec runtime PM held (the ACM service dies in D3), ACM work rescheduled
  on resume, DSP command-engine access serialised with a mutex, all UART waits sleep,
  and the ACM work runs on the unbound workqueue.
- HDA core: `patches/0001` flushes posted writes around the command-ring setup;
  without it the stock core hard-locks this controller.

---

## Other CA0132 cards

AE-5, AE-7, Z / Zx / ZxR and Recon3D are supported by the stock kernel driver and do
not need this package. If installed anyway, you get upstream `ca0132.c` plus the AE-9
work. That work was audited hunk by hunk against upstream; three changes run on every
CA0132 card and are behaviour-neutral (BAR2 posted-write readback, command-engine
mutex, 2 ms DSP reply polling). **None of it has been run on an AE-5 or AE-7.** The
AE-7's ACM is different hardware and its protocol has not been captured; the knob and
button support here is AE-9 only.

Reports and captures are welcome as GitHub issues. Run `tools/collect-report.sh`, look
it over, and attach the file.

---

## Credits

The original driver project this tree is based on is
**[`verzic/sb-ae9`](https://github.com/verzic/sb-ae9)** — the out-of-tree AE-9
driver, its HDA-core fix and the initial packaging.

The AE-9 changes in this branch were authored and tested on the same hardware by
**s3boun3t** and are ported from
[`s3boun3t/ae9_build`](https://github.com/s3boun3t/ae9_build) (GPL-2.0):

| Upstream commit | Change |
|---|---|
| `c06d416` | scope the HDA-core posted-write readbacks to the AE-9 |
| `fb4a88a`, `ebf33df` | bound the knob / button UART queries |
| `9925425` | auto-switch the output on the ACM headphone jack |
| `1343ebc` | shared `Headphone+LO` volume/switch for headphones and line-out |
| `da1e462` | align the hardware gain and the ACM volume display |
| `bb23212` | refresh the ACM display on mixer changes |

This tree adapts the ports to its own packaging: the auto-detect switch gates the jack
switching, and the install scripts, GUI and documentation use the shared
`Headphone+LO` control. Reviewed but deliberately not taken: `aef878a` (XanMod-specific
multiout ABI) and `0b2ce68` (enable mic/capture by default; kept opt-in for safety).

The base driver is the Linux kernel's `snd-hda-codec-ca0132`. Prior art: the
`ae9_build` project, which documented the card and the Windows registry; this work
started where it stopped (the DSP output stayed silent).

---

## License

GPL-2.0, derived from the Linux kernel. Creative's firmware and driver binaries are
not included and are not redistributed by any part of this project.
