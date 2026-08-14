"""Spike: the page index that makes a 45-page document fit a context window.

Measures the decision behind F4's chunk selection — OCR every page up front
(cheap, ~10s for 45 pages), then hand the model a compact INDEX rather than the
pages themselves. It plans over the index and pulls only the pages it wants.

Why not lazy per-page OCR: reading is not the constraint, context is. Lazy OCR
makes the agent spend 45 round-trips discovering what an index could have told it
in one, and it still cannot fit 45 pages of text in a window afterwards.

Run it — prints index tokens against full-text tokens, and self-checks:

    python3 spikes/page_index.py

A spike, not a layer: the Swift home for this is `Sources/Agent` at slice 4.2,
and this file dies with that move (`coding-standards.md` §1).

Cache lives in a temp dir and dies with the process: nothing is persisted.
Stdlib only.
"""

import atexit
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
OCR = ROOT / "ocr"
DPI = 150  # enough for Vision; 300 doubles render time for no measured CER gain


class Doc:
    """One document, fully OCR'd on construction."""

    def __init__(self, pdf: str | Path, dpi: int = DPI):
        self.pdf = Path(pdf)
        if not self.pdf.exists():
            raise FileNotFoundError(self.pdf)
        if not OCR.exists():
            raise FileNotFoundError(
                f"{OCR} is missing - it is a tracked launcher script, so this means "
                "a broken checkout, not a missing build")

        self._dir = Path(tempfile.mkdtemp(prefix="gdr-"))
        atexit.register(shutil.rmtree, self._dir, ignore_errors=True)

        subprocess.run(["pdftoppm", "-jpeg", "-r", str(dpi), str(self.pdf),
                        str(self._dir / "p")], check=True)
        imgs = sorted(self._dir.glob("p-*.jpg"))
        if not imgs:
            raise RuntimeError(f"no pages rendered from {self.pdf}")

        # One process; the ocr CLI runs the pages concurrently inside a TaskGroup.
        r = subprocess.run([str(OCR), "--json", *map(str, imgs)],
                           capture_output=True, text=True, check=True)
        self.pages = json.loads(r.stdout)  # index i == page i+1

    def __len__(self) -> int:
        return len(self.pages)

    def index(self) -> list[dict]:
        """One terse record per page. Empty fields are dropped to save tokens."""
        out = []
        for i, p in enumerate(self.pages, 1):
            confs = sorted(l["conf"] for l in p["lines"])
            e = {"page": i, "lines": len(p["lines"])}
            if confs:
                e["conf"] = [round(confs[0], 2), round(confs[len(confs) // 2], 2)]
            titles = [l["text"][:60] for l in p["lines"] if l["title"]][:2]
            if titles:
                e["titles"] = titles
            if p["data"]:
                e["data"] = p["data"]
            if p["tables"]:
                e["tables"] = p["tables"]
            if p["lists"]:
                e["lists"] = p["lists"]
            out.append(e)
        return out

    def read_page(self, n: int) -> str:
        """Full text of page n. 1-based, matching Finding.page in the output contract."""
        if not 1 <= n <= len(self.pages):
            raise IndexError(f"page {n} out of range 1..{len(self.pages)}")
        return self.pages[n - 1]["transcript"]

    def pages_with(self, kind: str) -> list[int]:
        """Page numbers whose detectedData fired for `kind` (measurement, calendarEvent, ...)."""
        return [i for i, p in enumerate(self.pages, 1) if p["data"].get(kind)]


def _tokens(obj) -> int:
    """Rough token count. chars/4 is close enough to size a context budget."""
    return len(json.dumps(obj, separators=(",", ":"))) // 4


def demo() -> None:
    pdf = ROOT / "assets/epa-labels/000524-00529-20241120.pdf"
    doc = Doc(pdf)
    idx = doc.index()

    assert len(doc) == 45, len(doc)
    assert len(idx) == 45
    assert [e["page"] for e in idx] == list(range(1, 46))

    # The premise of the whole design: the index must fit in a small context.
    tok = _tokens(idx)
    assert tok < 4096, f"index is {tok} tokens - too big to plan over"

    # read_page returns real text, and only for pages that exist.
    assert len(doc.read_page(1)) > 100
    try:
        doc.read_page(46)
        raise AssertionError("expected IndexError")
    except IndexError:
        pass

    # Every quote the agent shows must be liftable from a page (§6.2 substring rule).
    assert doc.read_page(1)[:40] in doc.read_page(1)

    print(f"pages           {len(doc)}")
    print(f"index size      {tok} tokens ({tok / len(doc):.0f}/page)")
    print(f"full text       {_tokens([p['transcript'] for p in doc.pages])} tokens "
          f"-- what you would have sent without an index")
    for kind in ("measurement", "calendarEvent", "moneyAmount", "postalAddress"):
        hits = doc.pages_with(kind)
        print(f"{kind:15} pages {hits if len(hits) <= 12 else str(hits[:12]) + '...'}")
    print("ok")


if __name__ == "__main__":
    demo()
