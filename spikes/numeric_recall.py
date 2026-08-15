#!/usr/bin/env python3
"""Numeric recall of one page: what fraction of the numbers in the file survive.

Spike for the docling question. Dies when the tracker records an answer, or
when `eval/ocr_bench.py` grows a `--numeric` column — whichever comes first.

The metric the progress tracker already reports ("numeric recall") and the one
that decides this product: a lost application rate is the failure it exists to
prevent. Order-insensitive and multiset, because a rate table read in the wrong
order is still readable, while `1.6` appearing 77 times and recovered 3 times is
not — a set would score that 1.0 and hide the whole failure.

Ground truth is free: every page in `assets/` is born-digital, so `pdftotext`
reads the numbers exactly. Nothing hand-labelled.

    ./ocr page34.jpg | python spikes/numeric_recall.py <pdf> 34
    python spikes/numeric_recall.py <pdf> 34 --self-check
"""

import re
import subprocess
import sys
from collections import Counter

# Matches how the tracker counted page 34: 186 tokens, `1.6` × 77, `0.8` × 47.
NUMBER = re.compile(r"\d+(?:\.\d+)?")


def numbers(text: str) -> Counter:
    return Counter(NUMBER.findall(text))


def truth(pdf: str, page: int) -> str:
    return subprocess.run(
        ["pdftotext", "-f", str(page), "-l", str(page), pdf, "-"],
        capture_output=True, text=True, check=True).stdout


def recall(want: Counter, got: Counter) -> tuple[int, int, Counter]:
    """Multiset recall, plus what went missing and how often."""
    kept = sum(min(n, got[tok]) for tok, n in want.items())
    lost = Counter({tok: n - min(n, got[tok]) for tok, n in want.items()})
    return kept, sum(want.values()), +lost  # unary + drops zero counts


def self_check() -> None:
    want = numbers("Hornbeam 1.6-4 0.8-1.6\nKudzu 3.2 1.6")
    assert want == Counter({"1.6": 3, "4": 1, "0.8": 1, "3.2": 1}), want

    # Everything read back.
    assert recall(want, want)[:2] == (6, 6)
    # Nothing read back — the page-34 case.
    assert recall(want, Counter())[:2] == (0, 6)
    # The trap a set-based metric falls into: one `1.6` recovered of three.
    kept, total, lost = recall(want, numbers("1.6"))
    assert (kept, total) == (1, 6), (kept, total)
    assert lost["1.6"] == 2, lost
    # A number the engine invented does not earn recall.
    assert recall(want, numbers("9.9 9.9 9.9"))[:2] == (0, 6)
    print("self-check ok")


def main() -> int:
    if "--self-check" in sys.argv:
        self_check()
        return 0
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2

    pdf, page = sys.argv[1], int(sys.argv[2])
    want = numbers(truth(pdf, page))
    got = numbers(sys.stdin.read())
    kept, total, lost = recall(want, got)

    print(f"numeric recall  {kept}/{total} = {kept / total:.1%}" if total
          else "no numbers on this page")
    if lost:
        print("lost:", ", ".join(f"{tok}×{n}" for tok, n in lost.most_common(8)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
