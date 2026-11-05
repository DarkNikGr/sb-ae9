# AE-9 upstream series

The split upstream series for Linux **v7.2**: 22 patches plus a cover
letter.  Every patch passes `scripts/checkpatch.pl --no-tree` with
**0 errors and 0 warnings**.

Apply from a clean v7.2 tree:

From the repository root, with the target kernel tree checked out:

```sh
git am patches/series/0001-*.patch patches/series/000[2-9]-*.patch \
       patches/series/001*.patch patches/series/002*.patch
```

`0000-cover-letter.patch` is only for the mailing-list submission; it has
no diff and must not be applied.

The series depends on the HDA-core posted-write flush in
`patches/0001-ALSA-hda-flush-posted-writes-around-the-command-ring.patch`.
Without it, probing the card hard-locks the machine.

The series was applied to a clean v7.2 tree with `git am`, and the
resulting `sound/hda/codecs/ca0132.c` builds against the 7.2.14 headers.
The squashed `patches/0002-...patch` is the same code for a quick read;
the split series is the submission form.
