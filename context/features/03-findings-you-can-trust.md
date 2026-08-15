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

### 3.4 Search is looser than validation, and that is the point

Extraction and validation use **different** patterns. One pattern for both jobs
silently drops the findings that matter most: OCR reads `10.5 0Z` for `10.5 oz`
on page 12 of the 45-page label, and a strict search never sees it — so the user
is never told the rate exists, let alone that its reading is doubtful.

Find it, then fail it. The row appears with `validated == false`; turning that
into a colour is 3.2's job. Discarding it is the app deciding for the reader,
which is the failure `project-overview.md` §9 is written against.

The widened character classes are the confusions measured in *this* corpus
(`0`/`O`, `1`/`l`/`I`), not a general OCR-error model. A real homoglyph table
belongs with 3.2's `topCandidates` signal, which sees the alternative readings
directly instead of guessing them.

### 3.5 There is no second way to build a `Finding`

`Finding` is `Encodable`, not `Codable`, and its initialiser is `package`. A
public initialiser — or a synthesised `Decodable` — is a second way in with no
transcript to check against, which would make **I2** a comment rather than a
rule. Decoding returns when there is an import path that carries the transcript
with it.

### 3.3 One construction point, because I2 is not a convention

```swift
func finding(label:value:quote:page:region:origin:validated:conf:in transcript:) -> Finding?
```

**I2** — every rendered value traces to a quote that is a verbatim substring of
the transcript. A caller cannot invent a quote because a caller cannot build a
`Finding` any other way. A quote that is not in the transcript yields nil rather
than throwing: one bad line must not cost the page its other findings.

### 3.6 The shape is not the claim (slice 3.4)

3.1 shipped one rule for finding a value: does it match the shape? Run over all
of `assets/` that produced **8,421 findings**, and reading them is what this
slice is. Three defects, all of the same kind — the shape was doing a job only
context can do.

**`\b\d{3,5}-\d{1,5}\b` matched 78 distinct values. Nine were registration
numbers.** The rest were phone numbers (`1-800-424-9300`), IRS notice numbers
(`2021-48`), OMB numbers (`1545-0074`), ZIP+4 (`20250-9410`) and EPA
establishment numbers (`2008-04-088-0099`) — and every one of them rendered
**checked**, because passing the shape is exactly what *checked* claimed. A
federal tax guide with the word EPA nowhere in it produced 42 of them. Precision
against a shape that common is not achievable by tightening the shape; it is
carried by the words on the line, and every genuine occurrence in the corpus sits
next to "EPA Reg. No." or "EPA Registration Number".

So `Format.cue`: words the line must carry before a shape may be claimed under
that name. It declines to *label* a value, it never discards one — the phone
number is still emitted by the detector that legitimately found it, which is
`the_phone_number_behind_a_rejected_registration_number_survives`.

**One value in one place was two rows.** The `amount` validator found 693
amounts on 120 pages of IRS P17; `moneyAmount` found 695 of the same ones. Two
rows there are not two facts. Findings now merge on value + region, and the
validator wins the collision because it is the half that can say no — keeping the
detector's row would throw away the `validated` flag §12 ranks highest.

**A date detector with no date in it.** Apple's `calendarEvent` read the EPA rate
tables as dates: `1.6-2.4`, `0.07 - 0.10`, and bare `Saturday` off the tax guide.
80 of 114 matches carried no date at all, and they land in the one group a reader
opens to find a deadline. A month name or a numeric `d/m` separates them, and
keeps every real date in the corpus — including `FEB 15 2011` off a rubber stamp.

### 3.7 Two questions, two tabs (slice 3.4)

The per-page list answers *what is on this page*. That is the F3 demo beat and it
stays. It is also the wrong question for a long document: IRS P17 produces
**2,064 findings over 120 pages**, and no amount of scrolling turns 17 rows a
page into "when is this due".

`Document.index` answers the other one — one row per distinct value, the pages it
appears on, searchable, filtered by `Kind`. Clicking a row walks its occurrences
and wraps, because a row that lists seven pages and goes dead on the seventh
click reads as broken.

`Kind` is a layer-0 type, not a string the view matches on: deciding that
`moneyAmount` and `Amount` are the same question is domain knowledge, and a view
that decided it would be layer 1's vocabulary leaking into layer 4
(`coding-standards.md` §1).

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
| **The misread rate** — page 12 of the 45-page label, where OCR reads `10.5 0Z` for `10.5 oz` | The finding is not dropped. `0Z` fails the `rate` validator, so it is emitted **unvalidated** rather than silently corrected or discarded. Flagging it is 3.2's job. **Tested** — `an_ocr_misread_rate_is_emitted_unvalidated`. This is why search and validation use *different* patterns (§3.4). |
| The same words twice on one page in two places | Two findings with two identities. One shared id highlights both rows and conflates two source locations. **Tested** — `the_same_value_in_two_places_gets_two_identities`. |

---

## 6.1 Stress test (slice 3.4)

| Case | Must happen |
|---|---|
| **`1-800-424-9300`** | Not a registration number, and still found as a phone number. **Tested** — `a_registration_number_is_claimed_only_where_the_line_says_so`, `the_phone_number_behind_a_rejected_registration_number_survives`. |
| **A tax guide with no EPA in it** | Zero registration numbers. It found 42. |
| **`$1,000` found by both producers** | One row, and it is the validator's. **Tested** — `one_value_in_one_place_is_one_row`. |
| **`1.6-2.4` read as a calendar event** | Not filed under Dates. **Tested** — `a_detected_date_with_no_date_in_it_is_not_a_date`. |
| **The cue line is itself misread** | The value is lost as a *registration number*, not lost. A recall cost paid on purpose against an 88% precision defect — and the honest reading of it, because the cue is a heuristic and §3.4's "find it and fail it" applies to values, not to labels. |
| A value on seven pages | One row that lists them and walks them. **Tested** — `a_row_walks_its_occurrences_in_page_order_and_wraps`. |
| The index against a real document | Loses no finding: occurrence counts sum to `findings.count`. **Tested** — `a_real_label_indexes_to_fewer_rows_than_it_has_findings`. |
| A search matching nothing | Names the query and says so. Never a blank panel. |
| A second document opened | Query and chip clear with the rest of the per-document state. |

---

## 7. Out of scope for 3.1

The confidence composite and its ring (3.2), thresholds (3.3), the
`assets/golden/kleister-charity/` 97-decoy count — that harness is the same
`ocr_bench.py` corpus-globbing rewrite slice 2.2 needs and belongs with it.

**Known ceiling, deliberate:** a finding's region is the whole line its quote
came from, not the matched words. Vision returns per-line boxes; word boxes need
a second request. F5 crops this region, so a tighter box is an upgrade, not a
fix — carried as a `ponytail:` comment in `Tools/Findings.swift`.


---

# Slice 3.2 — a confidence ring that can't lie

## 3.2.1 The two rules, and why they are not symmetrical

From `architecture.md` §12, and the asymmetry *is* the feature:

1. **Low confidence is a reliable trigger.** Genuine garbage clusters at the
   bottom — `WEAL PROTEIN` scored 0.062, 2nd lowest of 1092 lines. Below the
   escalate point is red.
2. **High confidence is not a licence to show green.** The four *highest* scores
   in the same corpus (0.885, 0.828, 0.824, 0.788) were all `口`, checkbox
   artifacts read as CJK glyphs. Green needs a reason beyond the score: a format
   validator passed, or the top candidates agree without a homoglyph
   substitution.

**I3** is the clamp: a failed validator can never render green, whatever the OCR
score, because a failed deterministic check is knowledge and no score argues
against it. **I4** is the floor: with nothing but the model's own self-report the
finding is **not scored** — not scored low. Those are different claims, and the
UI says `not scored` rather than painting a 0% ring.

## 3.2.2 What the homoglyph signal cost to make usable

| | lines | share |
|---|---|---|
| Total in `assets/scans/` | 1092 | — |
| *Some* candidate disagreement | 1024 | **93.8%** |
| **Homoglyph** disagreement | 8 | **0.7%** |

A signal that fires on 15 of every 16 lines cannot trigger escalation. Filtered
to homoglyph classes it fires on 1 in 128, worst page 4.3%. That gap is why §12
ranks raw disagreement low and this high — and why the test holds a ceiling at
15%, so widening the character classes cannot quietly turn a signal back into an
alarm.

## 3.2.3 Acceptance criteria (slice 3.2)

- [x] Validator failure clamps below green whatever the OCR score (**I3**) — **tested**, `a_failed_validator_can_never_render_green` over five scores
- [x] Composite requires ≥1 non-model signal (**I4**) — **tested**, `a_finding_with_only_model_self_report_cannot_be_scored`
- [x] `WEAL PROTEIN` at 0.062 renders red — **tested**
- [x] `lan Murphy` at 0.542 is flagged because candidate #2 is `Ian Murphy` — **tested**, `a_homoglyph_alternative_is_flagged`
- [x] Thresholds read from one `Thresholds` value — the composite is the only reader, and `scripts/layers.sh` keeps literals out of views

## 3.2.4 Stress test

| Case | Must happen |
|---|---|
| **The four `口` lines** at 0.885 / 0.828 / 0.824 / 0.788 | None renders green. **Tested** — `the_high_end_of_ocr_confidence_does_not_license_green`, table-driven over all four real scores. |
| **Every finding on the degraded scan through the composite** | None green without a validator pass or clean candidates. **Tested** — `no_real_finding_is_green_without_earning_it`. |
| **An all-caps page** (`0`/`O`, `I`/`l` everywhere) | False-flag rate recorded: 0.7% of all lines, 4.3% worst page. **Tested** with a 15% ceiling. |
| Confidence exactly at a threshold | Defined, not a `<` vs `<=` accident. **Tested** — at `escalate` it is amber, at `confident` it is green, one thousandth below `escalate` it is red. |
| A finding with model self-report only | Cannot be scored at all. **Tested** — the UI renders `not scored`, never a 0% ring. |

## 3.2.5 Known ceiling

The corpus maximum line confidence is **0.885** against a placeholder green cut
of **0.85**, so green is nearly unreachable today. The ring under-claims, which
is the right direction to be wrong — but it is effectively two-state until slice
**3.3** measures the real cut points. Carried, not hidden.