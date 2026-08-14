"""Stress-test the risky parts of the letter explainer before building it.

Each check is independent and prints PASS/FAIL. Run all, or name some:
    python spike.py                # everything
    python spike.py fixtures       # just regenerate demo letters
    python spike.py auth vision    # just those checks

The point is to answer, cheaply: do we need an OCR step at all, does one
structured call get us facts + evidence + uncertainty, and does the model
admit when it cannot read a field.
"""

import base64
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
FIX = HERE / "fixtures"

# Load .env before importing anthropic, so the SDK client sees the key.
for line in (HERE / ".env").read_text().splitlines() if (HERE / ".env").exists() else []:
    if "=" in line and not line.lstrip().startswith("#"):
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip("'\""))

import anthropic  # noqa: E402
from pydantic import BaseModel  # noqa: E402

MODEL = "claude-opus-5"
MAX_TOKENS = 8000  # thinking + verbatim transcription share this budget


# --- the output schema under test -------------------------------------------
# One call returns facts, evidence, uncertainty, AND a verbatim transcription.
# full_text is what makes the evidence quotes checkable (see check_quotes).

class Source(BaseModel):
    field: str
    quote: str   # exact words from the letter this value came from


class Letter(BaseModel):
    is_supported: bool
    reject_reason: str | None

    doc_type: str | None          # "missing documents request", "payment reminder", ...
    urgency: str | None           # urgent | soon | informational
    summary: list[str]            # 3-5 plain-language bullets

    deadline: str | None          # ISO if determinable
    deadline_raw: str | None      # the words the deadline came from
    office: str | None
    location: str | None
    appointment: str | None
    fee: str | None
    bring: list[str]              # documents to bring
    next_steps: list[str]

    sources: list[Source]
    guessed: list[str]            # fields inferred, not stated
    unreadable: list[str]         # fields present but not confidently read

    full_text: str                # verbatim transcription of the document


SYSTEM = """You explain an official letter to someone who does not understand it.

Extract only what the document actually says. Rules:
- `full_text` is a verbatim transcription. Transcribe what you see, including
  anything garbled. Do not clean it up, complete it, or guess at it.
- Every value in `sources` must quote words that appear verbatim in `full_text`.
- A field you cannot find is null. Never invent a value.
- A field you can see but cannot read confidently (blur, cut off, ambiguous)
  goes in `unreadable`, and its value stays null. Do not guess a date.
- `guessed` lists fields you inferred rather than read.
- `next_steps` are concrete actions the reader can take today. No legal advice.
- If this is not an official letter/notice, set is_supported false and put one
  sentence in reject_reason."""


def client() -> anthropic.Anthropic:
    return anthropic.Anthropic(max_retries=3, timeout=180.0)


def block(path: Path) -> dict:
    """A PDF or image file as a content block. Claude reads both natively."""
    data = base64.standard_b64encode(path.read_bytes()).decode()
    if path.suffix == ".pdf":
        return {"type": "document",
                "source": {"type": "base64", "media_type": "application/pdf", "data": data}}
    return {"type": "image",
            "source": {"type": "base64", "media_type": "image/png", "data": data}}


def read_letter(path: Path) -> Letter:
    r = client().messages.parse(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        system=SYSTEM,
        messages=[{"role": "user", "content": [
            block(path),
            {"type": "text", "text": "Explain this document and tell me what to do next."},
        ]}],
        output_format=Letter,
    )
    if r.parsed_output is None:
        raise RuntimeError(f"no parsed output: stop_reason={r.stop_reason}")
    return r.parsed_output


# --- fixtures ---------------------------------------------------------------
# Native macOS only: cupsfilter (text->PDF) and sips (PDF->PNG, degrade).
# No Pillow, no LaTeX, no browser.

CLEAN = """OFFICE OF THE REGISTRAR
Student Services Building, Room 212

NOTICE OF INCOMPLETE REGISTRATION - ACTION REQUIRED
Reference: REG-2026-04871

Dear Student,

Our records indicate that your registration file is incomplete. The
following document has not been received:

    - Proof of immunization (measles, mumps, rubella)

You must submit this document by Friday, 6 March 2026 at 3:00 PM. If it
is not received by that time, a registration hold will be placed on your
account and you will not be able to enrol in Fall term courses.

Bring the document in person to Room 212 with photo identification.
Office hours are Monday to Friday, 9:00 AM to 4:00 PM.

A late processing fee of $45.00 applies after the deadline.

Sincerely,
Office of the Registrar
"""

# The guardrail fixture. Two things are wrong on purpose: the scan is dirty
# (homoglyphs, dropped characters), and the deadline is *genuinely*
# underdetermined - it is relative to a notice date that is unreadable. No
# amount of OCR quality resolves that, so a model that reports a confident
# deadline here is guessing, and we want to catch it.
NOISY = """OFFICE OF THE REG!STRAR
Student Serv ces Building, Room 212

NOTICE OF INCOMPLETE REGISTRATION - ACTION REQUIRED
Refere ce: R G-2 26-O4871
Date of th s notice: ## ##### 2O26

Dear Student,

Our records ind cate that your registrat on file is incomplete. The
following document has not been rece ved:

    - Proof of immun zation (measles, mumps, rubella)

You must subm t this document w thin 10 business days of the date of
th s notice. If it is not rece ved by then, a registrat on hold will be
placed on your account.

Br ng the document in person to Room 212 with photo ident fication.

A late process ng fee of $45.OO applies after the deadl ne.

S ncerely,
Office of the Reg strar
"""

OFF_SCOPE = """Hey! Bringing snacks to the study group on Thursday.
Sam is picking up coffee. Text me if you want anything specific.
See you at the library, usual table.
"""


def run(*cmd, stdout=subprocess.DEVNULL):
    subprocess.run(cmd, check=True, stdout=stdout, stderr=subprocess.DEVNULL)


def make_fixture(name: str, text: str, degrade: bool = False) -> None:
    FIX.mkdir(exist_ok=True)
    txt, pdf, png = FIX / f"{name}.txt", FIX / f"{name}.pdf", FIX / f"{name}.png"
    txt.write_text(text)
    with pdf.open("wb") as f:
        run("cupsfilter", str(txt), stdout=f)
    run("sips", "-s", "format", "png", str(pdf), "--out", str(png))
    if degrade:
        # Downscale + rotate: stands in for a hurried phone photo.
        run("sips", "--resampleWidth", "620", "--rotate", "2", str(png))
    print(f"  wrote {pdf.name} ({pdf.stat().st_size}b) and {png.name} ({png.stat().st_size}b)")


def check_fixtures() -> bool:
    """Demo letters, built from nothing but macOS tools."""
    make_fixture("clean", CLEAN)
    make_fixture("noisy", NOISY, degrade=True)
    make_fixture("offscope", OFF_SCOPE)
    return True


# --- checks -----------------------------------------------------------------

def check_auth() -> bool:
    """Is there a working credential at all? Cheapest possible call."""
    r = client().messages.create(
        model=MODEL, max_tokens=16,
        messages=[{"role": "user", "content": "Reply with the word ready."}],
    )
    print(f"  model={r.model} stop={r.stop_reason} in={r.usage.input_tokens}")
    return True


def check_pdf() -> bool:
    """Does the PDF path work with no OCR step? (kills or keeps mere.run OCR)"""
    got = read_letter(FIX / "clean.pdf")
    print(f"  type={got.doc_type!r} deadline={got.deadline!r} urgency={got.urgency!r}")
    print(f"  transcribed {len(got.full_text)} chars")
    return got.is_supported and "immunization" in got.full_text.lower()


def check_vision() -> bool:
    """Same for a page image - the photograph-a-letter path."""
    got = read_letter(FIX / "clean.png")
    print(f"  type={got.doc_type!r} deadline={got.deadline!r}")
    print(f"  bring={got.bring} fee={got.fee!r}")
    return got.is_supported and "immunization" in got.full_text.lower()


def check_extract() -> bool:
    """Are the facts we promise the judges actually all there, in one call?"""
    got = read_letter(FIX / "clean.png")
    need = {
        "deadline": got.deadline and "03-06" in got.deadline,
        "fee": got.fee and "45" in got.fee,
        "location": got.location and "212" in got.location,
        "bring": len(got.bring) >= 2,
        "summary": 3 <= len(got.summary) <= 5,
        "next_steps": len(got.next_steps) >= 2,
        "sources": len(got.sources) >= 3,
    }
    for k, ok in need.items():
        print(f"  {'ok  ' if ok else 'MISS'} {k}: {getattr(got, k)!r}")
    return all(need.values())


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).casefold().strip()


def check_quotes() -> bool:
    """The honesty claim: is every evidence quote really in the document?

    A quote that is not a substring of the model's own transcription is an
    invented quote, and the whole 'source evidence' section is then theatre.
    """
    got = read_letter(FIX / "clean.png")
    haystack = norm(got.full_text)
    bad = [s for s in got.sources if norm(s.quote) not in haystack]
    for s in got.sources:
        mark = "ok  " if norm(s.quote) not in [norm(b.quote) for b in bad] else "FAKE"
        print(f"  {mark} {s.field}: {s.quote[:60]!r}")
    return not bad and len(got.sources) >= 3


def check_uncertainty() -> bool:
    """The guardrail demo: the deadline here is genuinely unknowable.

    It is "within 10 business days of the date of this notice" and the notice
    date is unreadable. A confident ISO deadline is therefore a fabrication.
    Passing means it left deadline null, or flagged it, or both.
    """
    got = read_letter(FIX / "noisy.png")
    flags = {f.casefold() for f in got.unreadable + got.guessed}
    print(f"  deadline={got.deadline!r} raw={got.deadline_raw!r}")
    print(f"  unreadable={got.unreadable} guessed={got.guessed}")
    print(f"  still read the rest: bring={got.bring} fee={got.fee!r}")
    fabricated = got.deadline is not None and not any("deadline" in f for f in flags)
    if fabricated:
        print("  ^ invented a date it cannot know - this is the failure to fix")
    # It must still be useful on the readable parts, not just refuse wholesale.
    return not fabricated and got.is_supported and bool(got.bring)


def check_refusal() -> bool:
    """Out-of-scope input: does it decline instead of forcing a letter shape?"""
    got = read_letter(FIX / "offscope.png")
    print(f"  is_supported={got.is_supported} reason={got.reject_reason!r}")
    return not got.is_supported and bool(got.reject_reason)


CHECKS = {
    "fixtures": check_fixtures,
    "auth": check_auth,
    "pdf": check_pdf,
    "vision": check_vision,
    "extract": check_extract,
    "quotes": check_quotes,
    "uncertainty": check_uncertainty,
    "refusal": check_refusal,
}


def main(names: list[str]) -> int:
    todo = names or list(CHECKS)
    unknown = [n for n in todo if n not in CHECKS]
    if unknown:
        print(f"unknown check(s): {unknown}. known: {list(CHECKS)}")
        return 2
    if any(n != "fixtures" for n in todo) and not os.environ.get("ANTHROPIC_API_KEY"):
        print("No ANTHROPIC_API_KEY. Put it in .env, then re-run.")
        print("Fixtures need no key:  python spike.py fixtures")
        return 2

    results = {}
    for name in todo:
        print(f"\n=== {name} ===")
        try:
            results[name] = CHECKS[name]()
        except Exception as exc:
            # ponytail: one traceback line is enough to spike a stack; add full
            # traceback if a failure stops being obvious from the message.
            print(f"  ERROR {type(exc).__name__}: {exc}")
            results[name] = False
        print(f"  -> {'PASS' if results[name] else 'FAIL'}")

    print("\n" + json.dumps({k: "PASS" if v else "FAIL" for k, v in results.items()}, indent=2))
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
