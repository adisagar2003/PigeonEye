"""Field Log agent: rambling voice note -> validated farm record.

Bounded loop: extract -> validate -> ask ONE question -> merge -> re-validate.
Hard cap at MAX_STEPS. Refuses to emit a row while a required field is blank.
"""

import csv
import io

import anthropic
from pydantic import BaseModel

MODEL = "claude-opus-5"
MAX_STEPS = 6          # bounded loop, shown on screen
MAX_ROUNDS = 3         # at most 3 clarifying questions

# Compliance-critical first. The agent asks about the earliest missing one.
REQUIRED = ["date", "field_name", "operation", "product", "rate"]
OPTIONAL = ["weather", "operator"]
ALL_FIELDS = REQUIRED + OPTIONAL


class Source(BaseModel):
    name: str    # which field
    phrase: str  # the exact words from the note it came from


class Extraction(BaseModel):
    is_field_record: bool
    reject_reason: str | None
    date: str | None
    field_name: str | None
    operation: str | None
    product: str | None
    rate: str | None
    weather: str | None
    operator: str | None
    sources: list[Source]
    guessed: list[str]   # fields inferred rather than stated


class Question(BaseModel):
    field: str
    text: str


EXTRACT_SYSTEM = """You turn a farmer's spoken field note into a compliance record.

Extract only what the note actually says. Rules:
- A field you cannot find in the note is null. Never invent a value.
- `sources` must quote the exact words from the note each value came from.
- `guessed` lists fields you inferred rather than read (e.g. today's date from
  "this morning"). A guessed field still needs a source phrase.
- Ambiguous references ("the north one", "the usual") are NOT a value. Leave
  the field null so the agent can ask.
- If the note is not about a field operation, set is_field_record false and put
  one sentence in reject_reason.

Fields: date (ISO if determinable), field_name, operation (spraying, seeding,
harvesting, tillage, fertilizing, scouting), product, rate (with units),
weather, operator."""

QUESTION_SYSTEM = """You are missing one required field from a farm record.
Ask the farmer ONE short, specific question to get it. Reference what they
already said so it sounds like a conversation, not a form. One sentence."""


def _client() -> anthropic.Anthropic:
    # SDK retries 429/5xx/connection errors with backoff. 4 total attempts.
    return anthropic.Anthropic(max_retries=3, timeout=120.0)


def extract(note: str, prior: dict | None = None) -> Extraction:
    """Note (plus any prior answers) -> structured record."""
    text = note.strip()
    if not text:
        return Extraction(
            is_field_record=False,
            reject_reason="Empty note - nothing to extract.",
            date=None, field_name=None, operation=None, product=None,
            rate=None, weather=None, operator=None, sources=[], guessed=[],
        )

    content = f"Field note:\n{text}"
    if prior:
        known = "\n".join(f"- {k}: {v}" for k, v in prior.items() if v)
        content += f"\n\nAlready confirmed by the farmer (trust these):\n{known}"

    r = _client().messages.parse(
        model=MODEL,
        max_tokens=4000,
        system=EXTRACT_SYSTEM,
        messages=[{"role": "user", "content": content}],
        output_format=Extraction,
    )
    if r.parsed_output is None:
        raise RuntimeError(f"extraction failed: stop_reason={r.stop_reason}")
    return r.parsed_output


def missing(rec: dict) -> list[str]:
    """Required fields still blank, in compliance-priority order."""
    return [f for f in REQUIRED if not rec.get(f)]


def ask(note: str, rec: dict, gap: str) -> Question:
    """The agent decides what to ask for the single most critical gap."""
    have = "\n".join(f"- {k}: {v}" for k, v in rec.items() if v) or "(nothing yet)"
    r = _client().messages.parse(
        model=MODEL,
        max_tokens=1000,
        system=QUESTION_SYSTEM,
        messages=[{
            "role": "user",
            "content": (
                f"Original note:\n{note}\n\nExtracted so far:\n{have}\n\n"
                f"Missing required field: {gap}"
            ),
        }],
        output_format=Question,
    )
    if r.parsed_output is None:
        return Question(field=gap, text=f"What was the {gap.replace('_', ' ')}?")
    return r.parsed_output


def to_record(e: Extraction) -> dict:
    return {f: getattr(e, f) for f in ALL_FIELDS}


def to_csv_row(rec: dict) -> str:
    buf = io.StringIO()
    csv.writer(buf, lineterminator="").writerow([rec.get(f) or "" for f in ALL_FIELDS])
    return buf.getvalue()


def demo():
    """Self-check for the pure logic. No API calls."""
    assert missing({}) == REQUIRED
    assert missing({f: "x" for f in REQUIRED}) == []
    # priority order preserved: date asked before rate
    assert missing({"field_name": "North 40", "operation": "spraying"})[0] == "date"
    # blank string counts as missing, not present
    assert "rate" in missing({f: "x" for f in REQUIRED} | {"rate": ""})

    # A comma/quote in a value must survive the round-trip without shifting columns.
    nasty = 'the "north" one, by the creek'
    row = to_csv_row({"date": "2026-08-14", "field_name": nasty})
    back = next(csv.reader([row]))
    assert len(back) == len(ALL_FIELDS), back
    assert back[ALL_FIELDS.index("field_name")] == nasty, back

    e = Extraction(
        is_field_record=True, reject_reason=None, date="2026-08-14",
        field_name=None, operation="spraying", product="Roundup", rate=None,
        weather=None, operator=None, sources=[], guessed=[],
    )
    assert missing(to_record(e)) == ["field_name", "rate"]
    print("agent.py self-check OK")


if __name__ == "__main__":
    demo()
