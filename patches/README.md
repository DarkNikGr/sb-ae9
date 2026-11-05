# Upstream patch series

These patches are the upstream-shaped version of the AE-9 work, based on
**Linux v7.2** (the `v7.2` tag).  Apply them in order:

1. `0001-ALSA-hda-flush-posted-writes-around-the-command-ring.patch`
   — generic HDA-core posted-write flush.  The AE-9 needs it; without it
   probing the card hard-locks the machine.
2. `0002-ALSA-hda-ca0132-add-Sound-Blaster-AE-9-support.patch`
   — CA0132 quirk, Windows-style bring-up, DSP loader/overlay, ACM UART,
   mixer controls, output routing, capture and Direct Mode.

Both pass `scripts/checkpatch.pl --no-tree` (0 errors, 0 warnings) and the
resulting sources build against the 7.2.14 kernel headers.

`0002` is still one large patch.  Before submission it should be split by
feature so the review is tractable, roughly:

- quirk ID, PCI table, pin configuration and the basic bring-up;
- DSP loader, ASI/PLL, the output-connect overlay and the 8051 hooks;
- ACM UART service, knob, display, buttons and SBX light;
- shared Headphone+LO volume and the AE-9 mixer controls;
- output routing / auto-detect;
- capture (main and secondary codec);
- Direct Mode and rate handling.

The **out-of-tree tree** in `driver/` is based on v7.0 and intentionally
keeps the scoped `hdac_bus_needs_posted_flush()` helper: the DKMS package
replaces `snd-hda-core` for every controller, so the readbacks should only
be paid on the AE-9.  `patches/0001` is the generic upstream version, where
the extra read is harmless on other controllers.

Creative's firmware and driver binaries are not included and are not
redistributed by this directory.
