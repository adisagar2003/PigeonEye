"""Run one eval case against any OpenAI-compatible /v1 endpoint.

Same prompt as spike_fm.swift, so the comparison is fair. Prints only the
model's answer on stdout, so it pipes into score.py exactly like spike_fm does.

    # mere.run, after: mere.run api serve
    python eval/openai_run.py epa-7969-242 --base-url http://localhost:8080/v1 \
        --model <whatever mere.run reports> | python eval/score.py epa-7969-242

    # OpenAI cloud
    OPENAI_API_KEY=sk-... python eval/openai_run.py epa-7969-242 | \
        python eval/score.py epa-7969-242

stdlib only - no `openai` package, no new dependency. mere.run's api serve and
OpenAI both speak this shape, which is the whole reason the local and cloud
paths can share one client.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent
CASES = json.loads((HERE / "cases.json").read_text())

# Byte-for-byte the prompt in spike_fm.swift. If you change one, change both.
INSTRUCTIONS = (
    "You explain official government documents to people who do not understand "
    "them. Use only what the document says. If a detail is not in the text, say "
    "it is not stated. Never invent dates, numbers, or names."
)

PROMPT = """Here is the OCR text of a government document.

1. What kind of document is this? One short phrase.
2. What does it say? Two or three plain sentences.
3. What, if anything, does the recipient have to DO? If nothing, say so.
4. List any dates, reference numbers, or deadlines, exactly as written.

---
{ocr}"""


def ocr(scan: str) -> str:
    """Run the project's local OCR so both candidates see identical input."""
    binary = ROOT / "ocr"
    if not binary.exists():
        sys.exit(f"{binary} is missing — it is a tracked launcher script, so this "
                 "means a broken checkout, not a missing build")
    r = subprocess.run([str(binary), str(ROOT / scan)],
                       capture_output=True, text=True)
    if not r.stdout.strip():
        sys.exit(f"OCR produced nothing for {scan}: {r.stderr.strip()}")
    return r.stdout


def main() -> int:
    real = [k for k in CASES if not k.startswith("_")]
    ap = argparse.ArgumentParser()
    ap.add_argument("case", choices=real)
    ap.add_argument("--base-url", default="https://api.openai.com/v1")
    ap.add_argument("--model", default="gpt-4o-mini")
    ap.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", "not-needed"))
    a = ap.parse_args()

    text = ocr(CASES[a.case]["scan"])
    print(f"input: {len(text)} chars via {a.base_url} ({a.model})", file=sys.stderr)

    body = json.dumps({
        "model": a.model,
        "messages": [
            {"role": "system", "content": INSTRUCTIONS},
            {"role": "user", "content": PROMPT.format(ocr=text)},
        ],
    }).encode()

    req = urllib.request.Request(
        f"{a.base_url.rstrip('/')}/chat/completions",
        data=body,
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {a.api_key}"},
    )

    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            payload = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:400]}")
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach {a.base_url}: {e.reason}\n"
                 f"(for mere.run, is `mere.run api serve` running?)")

    print(f"responded in {time.monotonic() - t0:.1f}s", file=sys.stderr)
    print(payload["choices"][0]["message"]["content"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
