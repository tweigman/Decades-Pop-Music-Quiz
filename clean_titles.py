#!/usr/bin/env python3
"""Add a quiz-friendly 'Clean Title' column to the tracks CSV.

Spotify track names carry release cruft: '- 2008 Remastered Version',
'- From "The Graduate" Soundtrack', '(Mono LP Version)'. This strips those
while preserving parentheticals that are genuinely part of the title --
'Sorry (I Ran All the Way Home)', '(What A) Wonderful World'.

The rule is keyword-driven, not positional: a trailing dash-clause or a
parenthetical is only removed when it *looks* like release metadata.
"""

import csv
import re
import sys

# Markers that identify a clause as release metadata rather than title text.
CRUFT = re.compile(
    r"""(?ix)
    \b(
        remaster(ed)? | re-?recorded | re-?issue
      | mono | stereo | digitally \s+ remastered
      | (single|album|lp|ep|original|alt\.?|alternate|extended|radio|edit(ed)?|short|long) \s+ (version|mix|edit|cut|take)
      | version | mix | edit | take \s*\d* | cut
      | live (\s+ (at|from|in|version))?
      | from \s+ ["“] | soundtrack | motion \s+ picture | original \s+ cast
      | bonus \s+ track | deluxe | anniversary
      | \d{4} \s+ (remaster|version|mix|recording)
    )\b
    """,
)

# Some clauses are pure years/labels appended after a dash: '- Buddha Remastered 2001'
DASH_SPLIT = re.compile(r"\s+-\s+")


def strip_parens(title):
    """Drop parenthetical/bracketed clauses that read as release metadata."""

    def drop(m):
        return "" if CRUFT.search(m.group(1)) else m.group(0)

    title = re.sub(r"\(([^()]*)\)", drop, title)
    title = re.sub(r"\[([^\[\]]*)\]", drop, title)
    return title


def clean(title):
    # A dash-clause is cruft if it (or anything after it) smells like metadata.
    parts = DASH_SPLIT.split(title)
    if len(parts) > 1:
        kept = [parts[0]]
        for p in parts[1:]:
            if CRUFT.search(p):
                break  # everything from here on is release metadata
            kept.append(p)
        title = " - ".join(kept)

    title = strip_parens(title)
    title = re.sub(r"\s{2,}", " ", title).strip()
    title = re.sub(r"[\s,\-–—]+$", "", title).strip()
    return title


def main(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))

    fields = ["#", "URL", "Title", "Clean Title", "Artist(s)", "Year", "Error"]
    changed = []
    for r in rows:
        r["Clean Title"] = clean(r["Title"])
        if r["Clean Title"] != r["Title"]:
            changed.append(r)

    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f"{len(changed)} titles cleaned of {len(rows)}\n")
    for r in changed:
        print(f"  {r['Title']}\n    -> {r['Clean Title']}")


if __name__ == "__main__":
    main(sys.argv[1])
