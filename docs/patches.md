<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Patches

## Numbering

The four-digit prefix is the bootstrap version times 100. One hundred
numbers per version. Start at `xx00` for the first patch of that
version.

| Version | Prefix | Range        |
|---------|--------|--------------|
| 0.2     | 02     | 0200–0299    |
| 0.3     | 03     | 0300–0399    |
| 0.4     | 04     | 0400–0499    |
| 0.5     | 05     | 0500–0599    |
| 0.6     | 06     | 0600–0699    |
| 0.7     | 07     | 0700–0799    |
| 0.8     | 08     | 0800–0899    |
| 0.9     | 09     | 0900–0999    |
| 1.0     | 10     | 1000–1099    |
| 1.1     | 11     | 1100–1199    |

Later versions follow the same rule (`2.0` → 2000–2099).

## Generating

From the `mislinux/` checkout, after the commit:

```
git format-patch -1 -o .. --start-number NNN
```

`NNN` is the next free number in the current version's range  (0400 for the
first 0.4 patch, 0401 for the next, and so on). Rename the file if the subject
slug is too long; keep the number prefix.

## Applying

```
git am ../04xx-subject.patch
```

Or `git apply` when the patch should not create a commit.
