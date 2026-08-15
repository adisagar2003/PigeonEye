#!/usr/bin/env python3
"""Does each number stay attached to the words that identify it?

Companion to `numeric_recall.py`, which is deliberately order-insensitive and so
cannot see this. Recall says the token `1.6` survived; it does not say `1.6`
survived *as the broadcast rate for Hornbeam*. On a rate table that difference is
the whole product: a rate attached to the wrong species is a confident wrong
answer, which is worse than a missing one.

    row  = one ground-truth line that has a key and at least one number
    key  = the text before the first number on that line ("Hornbeam, American*")
    kept = the hypothesis has a line for that key carrying the SAME numbers in
           the SAME order

Ground truth is `pdftotext -layout`, which preserves the column alignment the
plain mode throws away — verified by eye against page 34 before trusting it.

    swift spikes/spike_pdftext.swift <pdf> 34 | python3 spikes/row_integrity.py <pdf> 34
    python3 spikes/row_integrity.py --self-check
"""

import re
import subprocess
import sys

NUMBER = re.compile(r"\d+(?:\.\d+)?")
# Markdown table pipes and leading list marks, so docling's output is comparable
# to a flat text layer rather than being scored on its punctuation.
NOISE = re.compile(r"[|*_`]+")


def clean(line: str) -> str:
    return " ".join(NOISE.sub(" ", line).split()).lower()


def rows(text: str) -> list[tuple[str, list[str]]]:
    """(key, numbers-in-order) for every line that has both."""
    out = []
    for line in text.splitlines():
        flat = clean(line)
        first = NUMBER.search(flat)
        if not first:
            continue
        key = flat[: first.start()].strip(" .:-")
        # A key needs a letter in it; a line that opens with a number is a
        # column header or a page number, not a labelled row.
        if not key or not any(c.isalpha() for c in key):
            continue
        out.append((key, NUMBER.findall(flat)))
    return out


def integrity(truth: list, hyp_text: str) -> tuple[int, int, list]:
    hyp = rows(hyp_text)
    kept, broken = 0, []
    for key, want in truth:
        # The hypothesis may have merged or split lines, so match on the key
        # appearing anywhere in a line rather than on the line being equal.
        got = next((nums for k, nums in hyp if key in k or k in key), None)
        if got == want:
            kept += 1
        else:
            broken.append((key, want, got))
    return kept, len(truth), broken


def truth_text(pdf: str, page: int) -> str:
    return subprocess.run(
        ["pdftotext", "-layout", "-f", str(page), "-l", str(page), pdf, "-"],
        capture_output=True, text=True, check=True).stdout


def self_check() -> None:
    truth = rows("Chamise*      1.6-4    0.8\nCoyote brush  2.4-3.2  1.2-1.6")
    assert truth == [("chamise", ["1.6", "4", "0.8"]),
                     ("coyote brush", ["2.4", "3.2", "1.2", "1.6"])], truth

    # Same rows, single-spaced the way a text layer returns them.
    assert integrity(truth, "Chamise* 1.6-4 0.8\nCoyote brush 2.4-3.2 1.2-1.6")[:2] == (2, 2)
    # Markdown pipes must not change the verdict.
    assert integrity(truth, "| Chamise* | 1.6-4 | 0.8 |\n| Coyote brush | 2.4-3.2 | 1.2-1.6 |")[:2] == (2, 2)
    # The failure this metric exists for: both numbers present, wrong row.
    kept, total, broken = integrity(truth, "Chamise* 2.4-3.2 1.2-1.6\nCoyote brush 1.6-4 0.8")
    assert (kept, total) == (0, 2), (kept, total)
    # A dropped column is caught even though the species survived.
    assert integrity(truth, "Chamise* 1.6-4\nCoyote brush 2.4-3.2 1.2-1.6")[0] == 1
    # A row missing entirely is not silently skipped.
    assert integrity(truth, "Coyote brush 2.4-3.2 1.2-1.6")[0] == 1
    # A line opening with a number is a page number, not a row.
    assert rows("33") == []
    print("self-check ok")


def main() -> int:
    if "--self-check" in sys.argv:
        self_check()
        return 0
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2

    pdf, page = sys.argv[1], int(sys.argv[2])
    truth = rows(truth_text(pdf, page))
    kept, total, broken = integrity(truth, sys.stdin.read())

    print(f"row integrity  {kept}/{total} = {kept / total:.1%}" if total
          else "no labelled rows on this page")
    for key, want, got in broken[:5]:
        print(f"  broken: {key!r} want {want} got {got}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
