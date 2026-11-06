# AE-9 upstream series

The split upstream series for the current **sound.git `for-next`** branch
(Linux v7.2 plus the later ca0132 changes, including the AE-5 LED strip
work): 24 patches plus a cover letter.  Every patch passes
`scripts/checkpatch.pl --no-tree` with **0 errors and 0 warnings**.

Apply on top of a clean `sound` `for-next` checkout:

```sh
git am patches/series/0001-*.patch patches/series/000[2-9]-*.patch \
       patches/series/001*.patch patches/series/002*.patch
```

`0000-cover-letter.patch` is only for the mailing-list submission; it has
no diff and must not be applied.

The series depends on the HDA-core posted-write flush in
`patches/0001-ALSA-hda-flush-posted-writes-around-the-command-ring.patch`.
Without it, probing the card hard-locks the machine.  That patch also
applies cleanly to the current `for-next`.

The series was applied to a clean `for-next` tree with plain `git am`
(no three-way merge), and the resulting `sound/hda/codecs/ca0132.c`
builds against the 7.2.14 headers.  The squashed
`patches/0002-...patch` is the same code for a quick read; the split
series is the submission form.

The output-switch patch also carries the analog 5.1 work: rear pair on
codec pin `0x11`, the SABRE9006 mute for headphones and the balanced DSP
output trims.  The pin-detection patch marks the line-out pins
`NO_PRESENCE`, so ACP keeps every analog profile available.
