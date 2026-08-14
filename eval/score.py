"""Score a candidate model's reading of a government document.

One scorer, any model. Pipe the model's raw text answer in on stdin:

    ./ocr assets/scans/007969-00242-20170111-01.jpg | ./spike_fm | \
        python eval/score.py epa-7969-242

    python eval/openai_run.py epa-7969-242 --base-url http://localhost:8080/v1 | \
        python eval/score.py epa-7969-242

Deliberately scores plain prose, not JSON. Whether a model can be coerced into a
schema is a separate question from whether it read the document correctly, and
conflating them makes a weak model look broken and a strong one look fine.

Scoring is substring matching, case-insensitive, on purpose: it is inspectable
and it cannot silently award credit. Every hit and miss is printed.
"""

import json
import re
import sys
from pathlib import Path

CASES = json.loads((Path(__file__).parent / "cases.json").read_text())


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).casefold()


def any_hit(hay: str, needles) -> tuple[bool, str]:
    for n in needles:
        if norm(n) in hay:
            return True, n
    return False, ""


def score(case_id: str, output: str) -> int:
    case = CASES[case_id]
    hay = norm(output)
    exp = case["expect"]
    earned = possible = 0
    lines = []

    def check(label, ok, detail=""):
        nonlocal earned, possible
        possible += 1
        earned += ok
        lines.append(f"  {'PASS' if ok else 'FAIL'}  {label}{f' -> {detail}' if detail else ''}")

    # --- facts that must be read off the page --------------------------------
    for field in ("doc_type_keywords", "letter_date", "product", "contact",
                  "recipient", "action_keywords", "deadline_basis_keywords",
                  "deadline_derived"):
        if field not in exp:
            continue
        ok, hit = any_hit(hay, exp[field])
        check(field, ok, hit)

    for ref in exp.get("reference_numbers", []):
        check(f"reference {ref}", norm(ref) in hay)

    # --- did it get the direction of the document right? ---------------------
    if "action_required" in exp:
        claims_action = any(
            p in hay for p in ("you must", "must submit", "required to", "you need to")
        )
        want = exp["action_required"]
        check(f"action_required == {want}", claims_action == want,
              f"model {'claims' if claims_action else 'claims no'} action")

    # --- traps: these detect unsafe behaviour, not missing facts -------------
    for name, trap in case.get("traps", {}).items():
        if "fail_if_output_contains" in trap:
            bad, hit = any_hit(hay, trap["fail_if_output_contains"])
            possible += 1
            earned += not bad
            lines.append(f"  {'FAIL' if bad else 'PASS'}  trap:{name}"
                         f"{f' -> matched {hit!r}' if bad else ''}")
            if bad:
                lines.append(f"        why it matters: {trap['why']}")
        if "require_one_of" in trap:
            ok, hit = any_hit(hay, trap["require_one_of"])
            possible += 1
            earned += ok
            lines.append(f"  {'PASS' if ok else 'FAIL'}  trap:{name}"
                         f"{f' -> {hit}' if ok else ''}")
            if not ok:
                lines.append(f"        why it matters: {trap['why']}")

    print(f"\n=== {case_id} ===")
    print(f"  {case['notes']}")
    print("\n".join(lines))
    print(f"\n  SCORE {earned}/{possible}")
    return earned == possible


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in CASES:
        real = [k for k in CASES if not k.startswith("_")]
        print(f"usage: ... | python eval/score.py <case>\ncases: {real}")
        sys.exit(2)
    text = sys.stdin.read()
    if not text.strip():
        print("no model output on stdin")
        sys.exit(2)
    sys.exit(0 if score(sys.argv[1], text) else 1)
