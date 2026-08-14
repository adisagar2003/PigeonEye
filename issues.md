# Issues — Government Document Reader

Eight **end-to-end features**. Inside each, the thin **slices** that build it —
each slice a tracer bullet through every layer it needs, demoable on its own.

A feature is what the user can do. A slice is one sitting's work that leaves the
app more capable than it was, and never leaves it broken.

Product: `context/project-overview.md` · Stack, boundaries, invariants:
`context/architecture.md` · Status: `context/progress-tracker.md` ·
How code gets written: `coding-standards.md` · Agent rules: `ai-workflow.md`

**Conflict to resolve first.** The **Build order** table in
`context/progress-tracker.md` is horizontal — nothing renders until row 7. This
is vertical — something renders after slice 1.1. Both cannot be the source of
truth (`coding-standards.md` §1.1). Every slice names the build-order rows it
covers; either replace that table with this list or delete this file. Don't keep
two orderings.

Type: **AFK** = implementable and mergeable without a human decision.
**HITL** = needs a decision or judgement `context/` doesn't already contain.

---

## Feature map

| Feature | What the user can do | Slices | Blocked by |
|---|---|---|---|
| **F1 Read it locally** | Import a PDF, see what it says, know how much was read | 1.1 | — |
| **F2 Form mode** | See exactly the fields they must fill, zero inference | 2.1, 2.2 | F1 |
| **F3 Findings you can trust** | See the values that matter, each with a quote and an honest confidence | 3.1, 3.2, 3.3 | F1 |
| **F4 Explain it** | Read a plain-language summary, urgency and next steps | 4.1, 4.2, 4.3 | F3 |
| **F5 Escalate with consent** | Approve or skip sending an unclear crop, and get a result either way | 5.1, 5.2 | F3 |
| **F6 Fail honestly** | Get told what couldn't be read, never a blank or a bluff | 6.1 | F4 |
| **F7 Inspector mode** | See the step log, the signals, and exactly what was sent where | 7.1 | F3, F5 |
| **F8 Export** | Save the findings to a path they pick | 8.1 | F4 |

**Demo-complete after F6** — the three fixtures in `project-overview.md` §10 are
F2 (a form), F5 (a degraded scan with consented escalation) and F6 (an honest
refusal). F7 and F8 are upside.

**If the 24h runs short**, cut in this order: 8.1, 7.1, 2.2, 4.2+4.3. What
survives is a local reader with trustworthy findings, template prose, consented
escalation and honest failure — the whole pitch, minus polish.

---

# F1 · Read it locally

**The user can:** pick a government PDF and see, on their own machine with no
network, everything it says and how much of it was read.

**Feature demo:** open the 45-page EPA label, scroll the transcript, read
"pages 1–45 of 45" on screen.

**Done when:** 1.1 passes.

---

## 1.1 Open a PDF and see what it says

**Type:** AFK · **Blocked by:** none · **Rows:** 1

### What to build

A SwiftPM macOS app with `Sources/{Contracts,Tools,UI}`. `ocr.swift` moves to
`Sources/Tools/` and its layer-1 exemption dies with the move
(`coding-standards.md` §1). Pick a file → PDFKit renders it, Vision reads every
page, the transcript appears beside it, and "read pages 1–N of N" is on screen.

Boundary A converts coordinates to upper-left **once**, here. Nothing downstream
converts again (**I12**).

### Acceptance criteria

- [ ] `swift build` yields an app that opens `assets/epa-labels/000524-00529-20241120.pdf`
- [ ] Transcript shows Vision reading-order text for all 45 pages
- [ ] "read pages 1–45 of 45" rendered unconditionally, not behind a disclosure (**I5**)
- [ ] `Line` lives in `Sources/Contracts/`, bbox upper-left, asserted against a fixture line of known position
- [ ] The three layer greps in `coding-standards.md` §1 return empty
- [ ] Source file opened read-only; no write path to it (**I7**)

### Stress test

| Case | Must happen |
|---|---|
| **Crop round-trip** — crop the bbox of the topmost line on page 1, OCR the crop | Text equals that line. A vertical mirror passes eyeballing and fails this. |
| 45-page label, wall clock | Record the number. OCR alone measured 14.9s; if the app is 3× that, the render path is the problem, not Vision. |
| `assets/scans/*.jpg` at 100dpi/q40 | Lines come back; degraded is the normal path, not the edge |
| 0-byte file, `.txt` renamed `.pdf`, password-protected PDF | Named rejection each, no crash |
| 25 MB file | Rejected naming the actual size and the 20 MB limit |
| A PDF whose page 3 fails to render | Pages 1–2 and 4–45 still read; page 3 reported, not swallowed |

---

# F2 · Form mode

**The user can:** open a born-digital government form and get the exact list of
fields they must fill, read straight out of the file — nothing inferred, nothing
to hallucinate.

**Feature demo:** open IRS-4835, see 63 named fields, click one, watch the PDF
jump and highlight it. This is demo fixture #1 and the strongest claim the
product has.

**Done when:** 2.1 and 2.2 pass. 2.1 alone ships a usable feature with cryptic
IRS names; 2.2 makes it readable.

---

## 2.1 The fields you must fill

**Type:** AFK · **Blocked by:** 1.1 · **Rows:** 4

### What to build

If any page carries a `Widget` annotation, the document is a form. Read the
AcroForm widgets live from the file — never cached, never transcribed
(`coding-standards.md` §1.1) — and render the field list with page and rect.
`origin: acroform`, no confidence, no ring, no gate (`architecture.md` §9.1).

### Acceptance criteria

- [ ] IRS-4835 → 63 fields, Schedule F → 89, CPA-1200 → 105, counts asserted
- [ ] EPA label → 0 widgets → document mode, decided by the file not a guess
- [ ] `acroform` findings render without a confidence ring (**I3** doesn't apply)
- [ ] Clicking a field scrolls the PDFView to its page and highlights its rect

### Stress test

| Case | Must happen |
|---|---|
| **Highlight lands on the box** | PDFKit's rects are a *different* coordinate space from Vision's. A mirrored highlight here is a second I12 bug hiding behind the first one being fixed. |
| Checkbox and radio groups | No duplicated names, no dropped members — compare against the widget count, not the field-name count |
| CPA-1200's 105 fields | List scrolls without a stall |
| A widget on a page with no text at all | Field listed; 2.2 has nothing to find and must not crash |
| A widget whose rect is off-page or zero-sized | Listed, not rendered as a highlight covering the page |

---

## 2.2 Names for cryptic fields

**Type:** AFK · **Blocked by:** 2.1 · **Rows:** 4

### What to build

`topmostSubform[0].Page1[0].f1_04[0]` is not a label. For each widget rect, take
the nearest printed text from the OCR pass — left first, then above. Geometry,
not inference. The only place form mode touches OCR at all.

### Acceptance criteria

- [ ] IRS-4835 fields render human labels
- [ ] NRCS human-readable names are left alone — don't resolve what's already good
- [ ] Scored against `assets/golden/funsd/` question→answer links; the accuracy number goes in the tracker's **What measurement settled** (`ai-workflow.md` §4)

### Stress test

| Case | Must happen |
|---|---|
| **Two-column form** | Nearest-left must not grab the other column's text. This is the failure that makes the whole feature untrustworthy. |
| Label above and to the right (checkbox rows) | Either resolved or left as the raw name — never a confidently wrong neighbour |
| FUNSD scanner/fax noise | Accuracy reported honestly; a low number is a result, not a bug to hide |
| Widget with no text within any plausible distance | Falls back to the raw field name |
| Two widgets sharing one printed label | Both get it, or the pair is reported — silently assigning it to one is a lie |

---

# F3 · Findings you can trust

**The user can:** see the values that actually matter — rates, deadlines, reg
numbers, fees — each with the verbatim words it came from, a page to jump to,
and a confidence ring that is never green for the wrong reason.

**Feature demo:** open the degraded EPA scan, click a finding, land on the quote
in the PDF; point at the `口` artifact and show it is *not* green despite being
the highest OCR score in the corpus.

**Done when:** 3.1–3.3 pass. This is the feature the product is.

---

## 3.1 Deterministic findings

**Type:** AFK · **Blocked by:** 1.1 · **Rows:** 2, 3, 4

### What to build

The `Finding` contract (layer 0) plus the two deterministic producers: format
validators (EPA reg no., dates, amounts, form numbers, rate+unit) and Vision
`detectedData`. Each finding carries `value`, `quote`, `page`, `region`,
`validated`, `origin`. The quote-is-a-substring check lives at the single
construction point — one place, not per-caller.

A findings panel renders them; clicking one jumps to the page and highlights the
region.

### Acceptance criteria

- [ ] `assets/scans/007969-00242-20170111-01.jpg` yields findings including the "18 months" obligation, quoted verbatim
- [ ] A fabricated quote fails a test (**I2**)
- [ ] Table-driven validator test: `524-529` validates, `R G-2 26-O4871` does not
- [ ] `Finding` is the only shape — no parallel dictionaries or ad-hoc JSON anywhere (`coding-standards.md` §1.1)
- [ ] Click-to-jump lands on the right page with the region highlighted

### Stress test

| Case | Must happen |
|---|---|
| **The decoy date** — `epa-7969-242` has "Application Date: October 22, 2015" next to an 18-month relative deadline | The decoy is not emitted as the deadline. `eval/cases.json` already encodes this as `trap:wrong_deadline_anchor`. |
| **`assets/golden/kleister-charity/` 97 decoy keys** | Count how many become findings with a value. Target 0. Hallucination bait at a scale `assets/` can't reach. |
| **Page 12 of the 45-page label** — the mix-rate table, where OCR reads `10.5 0Z` for `10.5 oz` | The finding exists and its value is not silently wrong. 3.2 is what flags it; this slice must at least not drop it. |
| A page with zero findings | Renders "nothing found on this page", not blank (completeness rule) |
| 1092 lines through the panel | No stall |
| A validator given empty string / 10 KB of junk / unicode | Returns false, doesn't throw |

---

## 3.2 A confidence ring that can't lie

**Type:** AFK · **Blocked by:** 3.1 · **Rows:** 5

### What to build

The composite from `architecture.md` §12, and the ring that renders it. Signals:
validator result (highest), Vision low-end confidence, homoglyph disagreement in
`topCandidates`, model self-report (tiebreak only). The asymmetry is the point —
low confidence triggers escalation, high confidence does **not** license green.

### Acceptance criteria

- [ ] Validator failure clamps below green whatever the OCR score (**I3**)
- [ ] Composite requires ≥1 non-model signal (**I4**)
- [ ] `WEAL PROTEIN` at 0.062 renders red
- [ ] `lan Murphy` at a mid 0.542 is flagged, because candidate #2 is `Ian Murphy`
- [ ] Thresholds read from one `Thresholds` value; grep finds no confidence literal in a view or the agent

### Stress test

| Case | Must happen |
|---|---|
| **The four `口` lines** at 0.885 / 0.828 / 0.824 / 0.788 — the corpus's highest scores and its worst garbage | None renders green. If any does, rule 2 isn't wired and the ring is decoration with a number painted on it. |
| **All 1092 lines through the composite** | No non-`acroform` finding is green without a validator pass or clean candidates |
| **An all-caps page** (`0`/`O`, `I`/`l` everywhere) | Record the homoglyph false-flag rate. Too many flags and F5's gate escalates the whole document — that's a failure, not caution. |
| Confidence exactly at the threshold | Defined behaviour, tested, not a `<` vs `<=` accident |
| A finding with model self-report only | Cannot be scored at all (**I4**) |

---

## 3.3 Thresholds, picked from the distribution

**Type:** HITL · **Blocked by:** 3.2 · **Rows:** 5

Answers open question 3 in the tracker.

### What to build

A script that prints, for each candidate threshold: how many lines it escalates
across `assets/scans/` (1092 lines, min 0.054, p05 0.342, median 0.606, max
0.885) and how many crops it would send on each of the three demo fixtures. Then
you pick. Don't guess the numbers and don't let the model pick them.

### Acceptance criteria

- [ ] Table printed: threshold → escalated-region count per demo fixture
- [ ] Chosen numbers land in `Thresholds` and in the tracker's decision log, tagged *measurement*
- [ ] Open question 3 deleted from the tracker

### Stress test

| Case | Must happen |
|---|---|
| **The demo budget** | At the chosen point, how many crops does the 45-page label escalate? More than ~5 and the demo is a consent-dialog marathon. That count is the real acceptance bar, not the threshold's elegance. |
| Known-bad vs known-good | The seal misread escalates; `524-529` doesn't |
| Threshold applied to `assets/golden/` | Escalation rate on documents nothing was tuned on. A rate that only looks sane on `assets/scans/` is overfit. |

---

# F4 · Explain it

**The user can:** read one plain sentence naming the document, 3–5 summary
bullets, an urgency badge and a checklist of concrete next steps — with the
explanation still appearing when no model is available at all.

**Feature demo:** the same EPA letter explained with the model switched off,
then switched on. Identical layout; the model adds prose, never the difference
between a result and a blank screen.

**Done when:** 4.1 passes. 4.2 improves the prose, 4.3 settles which model.

---

## 4.1 Explanation without a model

**Type:** AFK · **Blocked by:** 3.1 · **Rows:** 4

### What to build

Tier-1 output — `doc_type`, `what_it_is`, `summary`, `urgency`, `next_steps` —
assembled from deterministic findings with **zero model calls**. This is the
fallback tier from the tracker, built first so that a failed or absent model
never blanks the screen. Urgency by consequence, not by days remaining.

### Acceptance criteria

- [ ] All three demo fixtures render complete tier-1 output with no model call
- [ ] Urgency assigned by consequence rule (an EPA label may bind with no date at all)
- [ ] A document with zero findings still renders a summary and next steps

### Stress test

| Case | Must happen |
|---|---|
| **`epa-524-529` requires nothing of the recipient** | No obligation-shaped next step is invented. A template that always emits "you must…" fails here. |
| **`epa-7969-242` carries a real obligation** | It appears |
| Zero findings | Summary and checklist still render (completeness rule) — gaps marked, not hidden |
| A form (F2 path) | Tier-1 doesn't fabricate prose over a field list |

---

## 4.2 Explanation from a model, swappable

**Type:** AFK · **Blocked by:** 4.1 · **Rows:** 4

### What to build

One OpenAI-compatible client with a configurable base URL — `localhost` for
mere.run, `api.openai.com` for cloud, identical request shape. Chunked per
`architecture.md` §3.1 (paragraph / table / list), map-reduced into tier 1. Any
failure falls back to 4.1's output.

### Acceptance criteria

- [ ] `eval/score.py` run on both cases; scores recorded in the tracker
- [ ] Estimated tokens asserted below the window before every call (**I13**)
- [ ] Chunk loop bounded — hard cap on chunks per document and calls per chunk (**I10**)
- [ ] Model unavailable → 4.1's output, screen never blank
- [ ] Every model-produced value still passes the **I2** quote check

### Stress test

| Case | Must happen |
|---|---|
| **`trap:wrong_deadline_anchor`** | Does not fire. The scorer already discriminates — a hand-written dangerous answer scored 10/12 and failed exactly this. |
| A chunk larger than the window | Splits and proceeds; does not throw at runtime on the one document that matters |
| Model invents a number not in the transcript | Rejected by **I2**, not rendered |
| **45 pages of chunks, wall clock** | Record it. If it's beyond demo-tolerable, chunk selection uses the page index (`tools.py`, 1,426 tokens vs 32,394) rather than every chunk. |
| Endpoint returns 200 with an empty body | Falls back, doesn't render an empty summary as success |

---

## 4.3 Pick the local reasoning tier

**Type:** HITL · **Blocked by:** 4.2

Answers open question 1 — and with it the zero-download pitch and the
native-vs-cross-platform coupling (`architecture.md` §3.2). One decision, not two.

### What to build

Nothing new. Enable Apple Intelligence, run `spike_fm` through `eval/score.py`,
run the same cases through OpenAI, compare. Then decide: Apple FM, mere.run, or
cloud-only.

### Acceptance criteria

- [ ] Both scores recorded in **What measurement settled** with how they were produced
- [ ] Decision in the log; `architecture.md` §5 and the zero-download claim updated to match
- [ ] Open question 1 deleted

### Stress test

| Case | Must happen |
|---|---|
| **Score on something not tuned on** | `assets/golden/govreport/` — two EPA letters cannot settle a model choice. A tier that wins on the tuned cases and loses here was overfit by the person picking it. |
| FM latency per page | Measured, not assumed. Latency was flagged untested in `architecture.md` §3.1 and it's the risk, not context. |
| mere.run, if considered | Count the disk and the pull honestly — ~5 GB build, ~2 GB model, a pinned personal fork of mlx-swift in the graph |

---

# F5 · Escalate with consent

**The user can:** be shown the exact crop the app wants help reading, approve or
skip it, and get a rendered result either way — the trust boundary, working.

**Feature demo:** the degraded EPA scan. Skip everything → result renders with
unresolved fields. Run again, approve one crop → that field resolves and is
marked escalated. This is demo fixture #2.

**Done when:** 5.1 and 5.2 pass. 5.1 alone is a complete, shippable feature —
consent that never sends anything, which is what makes **I11** and **I6** true
by construction rather than by a later error handler.

---

## 5.1 Ask or skip, with nothing leaving

**Type:** AFK · **Blocked by:** 3.2 · **Rows:** 6, 9

### What to build

The gate. Regions below threshold produce a crop preview showing the exact
pixels that would be sent, and an ask/skip choice. **No network code in this
slice.** Skip marks the field unresolved and renders the result.

### Acceptance criteria

- [ ] Low-confidence regions render a crop preview of the actual pixels
- [ ] Skip → full result renders, fields marked unresolved (**I11**)
- [ ] `rg 'URLSession|http' Sources` is still empty — no egress exists yet
- [ ] Nothing about the document reaches a log (`coding-standards.md` §5.2)

### Stress test

| Case | Must happen |
|---|---|
| **Preview pixels == highlight pixels** | The crop shown and the region highlighted are the same rect. This is the third and most visible I12 check — if the earlier two were wrong in compensating directions, this is where it shows. |
| Zero low-confidence regions | Gate never appears; result renders straight through |
| 30 low-confidence regions | The gate caps and says what it capped. An unbounded consent wall is the same as no consent. |
| Skip everything, then approve everything | Both render; neither leaves state behind |
| A region at the page edge / spanning two columns | Crop is a valid image, not a zero-width rect |

---

## 5.2 The one egress: consented crops out

**Type:** AFK · **Blocked by:** 5.1 · **Rows:** 6

### What to build

One function in `Sources/Gate/` that sends approved crops to OpenAI and merges
the answers back. The only place bytes cross the trust boundary. Merged findings
are marked escalated; local values survive regardless (**I6**).

### Acceptance criteria

- [ ] A test asserts the payload contains only regions in the approved set (**I1**)
- [ ] No source file, no whole page, no transcript in the request body
- [ ] Timeout, 429, 500, and missing key all fall through to local results
- [ ] Key from Keychain or env; never logged, never rendered
- [ ] `rg 'URLSession|http' Sources | grep -v '^Sources/Gate/'` empty

### Stress test

| Case | Must happen |
|---|---|
| **Approve 1 of 3 crops** | Exactly one image in the payload, asserted byte-wise against the approved crop. This is I1's real test; a count check would pass while sending the wrong crop. |
| Network pulled mid-call | Local results stand, marked unresolved |
| API returns non-JSON / an apology / an invented number | Retry once, then keep local. An invented value must still fail the **I2** quote check. |
| No key set | Says so once, renders local results |
| **Log scrape after a full run** | No filename, path, key, crop bytes, or document text in any line (`coding-standards.md` §5.2) |
| Cloud answer disagrees with the local read | Both visible; escalated marker shown. Silent overwrite is the failure. |

---

# F6 · Fail honestly

**The user can:** hand over something the app can't handle and be told plainly
what happened, while still seeing everything that *was* read.

**Feature demo:** an out-of-scope document — demo fixture #3.

**Done when:** 6.1 passes.

---

## 6.1 Honest refusal

**Type:** AFK · **Blocked by:** 4.1

### What to build

The two paths that must not be dead ends: not-a-government-document, and
too-degraded-to-OCR. Both render what *was* read.

### Acceptance criteria

- [ ] Non-government document → says so plainly, no schema forced onto it
- [ ] OCR failure → reports the failure and what to try; never an empty result dressed as success
- [ ] Both still render the transcript and pages-read

### Stress test

| Case | Must happen |
|---|---|
| A blank scan | "OCR found nothing", not a confident empty summary |
| A photo with text but no document structure | Honest refusal, not a forced `doc_type` |
| A non-English government document | Named limitation — `assets/golden/` is English/US-UK only, so this is untested territory and must say so |
| **A 45-page document where only page 3 is unreadable** | Not a refusal. Page 3 is marked; the other 44 produce a full result. Whole-document refusal on a partial failure is the bug this case exists to catch. |

---

# F7 · Inspector mode

**The user can:** flip a dev toggle and see the step log, the per-signal
confidence breakdown, and exactly what was sent where.

**Feature demo:** consumer mode proves it's usable; this proves the agent is
real and the confidence number isn't painted on.

**Done when:** 7.1 passes.

---

## 7.1 Inspector mode

**Type:** AFK · **Blocked by:** 3.2, 5.2 · **Rows:** 8

### What to build

The dev toggle: step log, per-signal confidence breakdown, and exactly what was
sent where. Consumer mode shows none of it.

### Acceptance criteria

- [ ] Every ring's signal breakdown visible (which signal produced which number)
- [ ] Escalations listed with what left and when
- [ ] Consumer mode shows no logs, no internals

### Stress test

| Case | Must happen |
|---|---|
| **Inspector log content** | The breakdown renders in the UI; the *log sink* still contains no document text, filename, path, or key. Inspector mode is a view, not an exemption from §5.2. |
| Toggle mid-session | State survives; no re-run |
| A document with 200 findings | The log is navigable, not a wall |

---

# F8 · Export

**The user can:** save the findings to a path they choose. The app's only write.

**Done when:** 8.1 passes.

---

## 8.1 Export

**Type:** HITL (format) → AFK (build) · **Blocked by:** 4.1

Answers open question 2.

### What to build

Decide Markdown / CSV / JSON, then write findings to a path the user picks.

### Acceptance criteria

- [ ] User picks the path; no default location is written to
- [ ] Findings only — no document bytes, no crops (**I8**, **I9**)
- [ ] Format decision in the log; open question 2 deleted

### Stress test

| Case | Must happen |
|---|---|
| Export after skipping every escalation | Unresolved fields exported as unresolved, not omitted |
| Export a 105-field form | Complete, not truncated |
| Path is unwritable / disk full | Named failure, nothing half-written |
| **Grep the exported file** | No crop bytes, no key, no source path |
