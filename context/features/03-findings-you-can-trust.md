# F3 · Findings you can trust

**The user can** see the values that actually matter — rates, deadlines,
registration numbers, amounts — each with the verbatim words it came from and a
page to jump to.

Product · `../project-overview.md` §5 ·
Contract and invariants · `../architecture.md` §11 (output contract), §12
(confidence composite), §8 (**I2**, **I3**, **I4**) ·
Status · `../progress-tracker.md` ·
How code gets written · `../coding-standards.md` ·
Agent rules · `../../ai-workflow.md` ·
Slices · `../../issues.md` F3

**Precedence.** Where this file and `context/` disagree, `context/` wins.

---

## 1. Demo

Open `assets/scans/007969-00242-20170111-01.jpg`. The rail lists what was found
on the page: the EPA registration number **7969-242**, marked *checked* because a
format validator passed it, and the **18 months** window the letter's whole
obligation hangs on — each shown with the sentence it was quoted from. Click one
and the page outlines the line it came from.

---

## 2. Settled before writing this

| Question | Answer | Whose |
|---|---|---|
| What produces a finding in 3.1? | Two deterministic producers only: format validators and Apple's data detectors. No model | `issues.md` 3.1 |
| Where is **I2** enforced? | At the single construction point, not per caller | `issues.md` 3.1 |
| Where do validators live? | Rules (`Format`) in Contracts, regexes in Tools | `coding-standards.md` §1 |
| Does 3.1 render a confidence ring? | **No.** That is 3.2. §12 is explicit that a number rendered before it is composed from real signals is decoration | `architecture.md` §12 |

Measured while scoping — `swift run ocr assets/scans/007969-00242-20170111-01.jpg`
confirms both targets are actually in the text this corpus produces:

```
EPA Registration Number: 7969-242
… you may distribute or sell this product under the previously approved
labeling for 18 months from the date of this letter. After 18 months, …
```

The `18 months` window appears twice in one sentence, on one line, so it has one
region and one row — deduplication is a real requirement, not a precaution.

---

## 3. Contract

### 3.1 What each layer holds

| Layer | Target | Holds |
|---|---|---|
| 0 | `Contracts` | `Finding` (already shipped, unused until now), `Format` — the rule identity and its on-screen label |
| 1 | `Tools` | `validate(_:using:)`, `findings(on:number:)`, and `finding(…)` — the one construction point |
| 2 | `Agent` | `Document.findings`, built per page after OCR; one step-log line of counts |
| 4 | `UI` | The findings panel, click-to-jump, and the highlight overlay shared with form mode |

### 3.2 Validators are whole-match, deliberately

```swift
public func validate(_ text: String, using format: Format) -> Bool
```

A *containment* check would pass `R G-2 26-O4871` the moment any fragment of it
looked like a registration number — and that string is a real Vision misread from
this corpus, not a hypothetical. Whole-match is what makes the validator able to
say no, which is the only reason §12 ranks it the highest-trust signal there is.

Extraction is separate: the same pattern is *searched* across a line to find
candidates, then each candidate is validated in full.

### 3.3 One construction point, because I2 is not a convention

```swift
func finding(label:value:quote:page:region:origin:validated:conf:in transcript:) -> Finding?
```

**I2** — every rendered value traces to a quote that is a verbatim substring of
the transcript. A caller cannot invent a quote because a caller cannot build a
`Finding` any other way. A quote that is not in the transcript yields nil rather
than throwing: one bad line must not cost the page its other findings.

---

## 4. TDD flow

| # | Red — write this test first | The failure you should read | Green |
|---|---|---|---|
| 1 | `epa_registration_numbers_validate_and_garbage_does_not` — `524-529` yes, `R G-2 26-O4871` no | `cannot find 'validate' in scope` | `Format` in layer 0, its regex in Tools |
| 2 | `a_validator_survives_junk` — empty, 12 KB, unicode, whitespace → false | — | guard on empty, whole-match on the rest |
| 3 | `a_fabricated_quote_is_refused` — a quote absent from the transcript yields nil | `a quote absent from the transcript was accepted — I2 is not enforced` | the substring guard at the one construction point |
| 4 | `every_finding_quotes_the_transcript_verbatim` — the same guard against a real page | — | falls out of #3 |
| 5 | `a_real_scan_yields_the_obligation_quoted_verbatim` — `7969-242` validated, and the 18-month window | `the 18-month window was not found` | a `duration` format; the corpus's obligations are relative windows, not dates |
| 6 | `the_decoy_date_and_the_relative_window_are_both_emitted` | — | emit both; choosing between them is F4's job |
| 7 | `a_page_with_no_text_yields_no_findings` | — | iterate lines, of which there are none |
| 8 | `findings_carry_the_page_they_were_found_on` — 1-based | — | the page is a parameter, not inferred |

---

## 5. Acceptance criteria (slice 3.1)

- [x] The real scan yields findings including the 18-month obligation, quoted verbatim — **tested**, `a_real_scan_yields_the_obligation_quoted_verbatim`
- [x] A fabricated quote fails a test (**I2**) — **tested**, `a_fabricated_quote_is_refused`
- [x] Table-driven validator test: `524-529` validates, `R G-2 26-O4871` does not — **tested**
- [x] `Finding` is the only shape — no parallel dictionaries, no ad-hoc JSON
- [x] Click-to-jump lands on the right page with the region highlighted — shares one overlay with form mode
- [x] A page with zero findings renders "nothing found on page N", not blank

---

## 6. Stress test

| Case | Must happen |
|---|---|
| **The decoy date** — the letter carries an application date next to an 18-month relative window | Both are emitted as their own findings with their own quotes. 3.1 does not choose; a slice that dropped one would be making F4's choice invisibly. **Tested** — `the_decoy_date_and_the_relative_window_are_both_emitted`. |
| A validator given empty / 12 KB of junk / unicode | Returns false, does not throw. **Tested** — `a_validator_survives_junk`. |
| The same words twice on one line | One row. "18 months" appears twice in one sentence and both occurrences share a line, so they share a region and nothing tells them apart. Deduplicated on label + value + region. |
| A page with zero findings | "Nothing found on page N", never blank — the completeness rule. |
| Page 12 of the 45-page label, where OCR reads `10.5 0Z` for `10.5 oz` | The finding is not dropped. `0Z` fails the `rate` validator, so it is emitted **unvalidated** rather than silently corrected or discarded. Flagging it is 3.2's job. |

---

## 7. Out of scope for 3.1

The confidence composite and its ring (3.2), thresholds (3.3), the
`assets/golden/kleister-charity/` 97-decoy count — that harness is the same
`ocr_bench.py` corpus-globbing rewrite slice 2.2 needs and belongs with it.

**Known ceiling, deliberate:** a finding's region is the whole line its quote
came from, not the matched words. Vision returns per-line boxes; word boxes need
a second request. F5 crops this region, so a tighter box is an upgrade, not a
fix — carried as a `ponytail:` comment in `Tools/Findings.swift`.
