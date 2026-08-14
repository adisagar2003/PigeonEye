# Government Document Reader — Project Overview

Canonical project doc. Synthesised from the 20 review comments on `SPEC.md`
(2026-08-14) plus what is actually in the repo.

Every decision below is tagged:

- **[yours]** — you decided it in review
- **[mine]** — you said "decide for me"; I decided, change it freely
- **[open]** — still needs a decision, listed in §13

> `context/` did not exist when you referenced it — this file created the
> directory. If you have another copy of it elsewhere, say so and I'll merge.

---

## 1. Product

> Photograph or import a confusing government document and get back a
> plain-language explanation, the obligations and deadlines that actually
> matter, and a checklist of what to do next — read on your own machine, with
> every claim quoted from the source and every uncertain reading marked as
> uncertain.

**[yours]** Renamed from "Letter Explainer" to **Government Document Reader**.
The domain is government documents and complex documentation generally, not
campus letters.

Two things separate this from a summariser, and both are load-bearing:

1. **Nothing leaves the machine unless you say so.** The documents people
   least want to upload are the ones they most need read.
2. **It tells you where it is unsure.** A confident wrong date on a
   regulatory document is worse than no date.

---

## 2. User and problem

Someone who receives or must comply with an official document and cannot tell
what it obligates them to do. The failure they are avoiding is not confusion —
it is missing one line and losing money, access, or legal standing.

Based on `assets/`, the concrete user is **agricultural**: a farmer or farm
operator dealing with EPA pesticide labels, IRS farm tax forms, and NRCS
conservation paperwork. This is consistent with the pre-existing Field Log
prototype in the repo, which handled farm compliance records.

---

## 3. Scope — document families

**[yours]** Government documents; samples live in `assets/`.

What is actually there:

| Family | Files | Why it's a good demo |
|---|---|---|
| EPA pesticide labels / notifications | 6 PDFs in `assets/epa-labels/` | Dense, legally binding, real consequences for misreading. Application rates, restricted-entry intervals, PPE. |
| IRS farm tax forms | `ScheduleF`, `4835` in `assets/gov-forms/` | Everyone recognises the pain. Structured fields, two-column layouts. |
| NRCS conservation application | `CPA-1200` in `assets/gov-forms/` | Application deadlines and required attachments — the checklist output shines. |

**[mine]** §1.2 asked "how many document types must work live", which you
noted was unclear. Reframed and answered: **how many document families must
survive a live demo, given each one added is another fixture and another way
to fail on stage.**

Decision: **two families work properly, a third degrades honestly.**

- **Primary: EPA labels.** Most compelling stakes, and the misreads are real.
- **Secondary: IRS Schedule F.** Proves it handles structured forms and
  two-column layouts, not just prose.
- **Third: NRCS CPA-1200** — no tuning. If it works, bonus; if it half-works,
  that *is* the honesty demo.

---

## 4. Non-goals

**[mine]** You said "decide for me". Say no to all of these at hour 14:

| Non-goal | Why |
|---|---|
| Filing, submitting, or sending anything | One irreversible action ruins the trust story |
| Legal, tax, or compliance advice | It explains documents; it does not tell you your obligations are met |
| Accounts, login, persistence across sessions | Zero product value in 24h, and it contradicts the privacy pitch |
| Arbitrary document types outside §3 | Unbounded scope, unbounded failure |
| Camera capture | **[yours]** — file import only for MVP (§5) |
| Editing or annotating the source PDF | Different product |
| Fine-tuning or training anything | Not a 24h activity |
| Browser automation, RAG over regulation corpora, multi-agent orchestration | All were already ruled out; keeping them ruled out |

---

## 5. Architecture — local-first, escalate only what's uncertain

**[yours]** This is your design from the review, unchanged in substance:

```
1. IMPORT          PDF (and other doc formats) — file import only, no camera
                        │  render pages to images
                        ▼
2. LOCAL OCR       Apple Vision RecognizeDocumentsRequest  (ocr.swift)
                        │  text + reading order + regions
                        ▼
3. LOCAL EXTRACT   fill the output contract, score confidence per finding
                        │
                        ▼
4. CONFIDENCE GATE   any finding below threshold?
                        │
             no ────────┴──────── yes
              │                    │
              ▼                    ▼
        done, fully local    show the user EXACTLY which crops
        nothing left              would be sent, and ask
        the machine                    │
                            skip ──────┴────── allow
                              │                  │
                              ▼                  ▼
                     mark unresolved      crop ONLY those regions
                                          → cloud vision API
                                          → merge into findings
                        ▼
5. RENDER          findings + confidence rings + evidence quotes
                   + what was read and what wasn't
```

Properties that make this worth building:

- The **default path is fully local**. Cloud is an exception, not a tier.
- What gets sent is **a crop, not the document** — and the user sees the crop
  before it goes.
- The escalation decision is **driven by measured confidence**, not by a
  coin flip or a config flag.

**[yours]** Cloud provider: you're supplying an **OpenAI** key. Architecturally
this is not load-bearing — step 4 sends image crops, which any current vision
model handles — so the provider is swappable. Noting it because the earlier
work in this repo assumed `claude-opus-5`, which is now void (see §15).

### 5.1 Step 3 splits in two — this is the important structural decision

**[mine, from measurement — see §12]** "Local extraction" was one box in the
diagram. It has to be two, because the two halves have completely different
correctness requirements and completely different dependencies:

| | 3a. Field extraction | 3b. Explanation |
|---|---|---|
| Produces | dates, amounts, reg numbers, rates, offices | plain-language summary, next steps |
| Method | Vision structure + `detectedData` + format validators | a language model |
| Can it hallucinate? | **No** — every value is lifted from OCR output and validated | Yes |
| Cost of an error | Severe (wrong deadline on a regulatory document) | Mild (clumsy wording) |
| Runs today? | **Yes** — measured working, §12.2 | Only if Apple Intelligence is on, §12.1 |
| Needs a model? | No | Yes |

Why this split is the whole design: **the values that must be correct never
pass through a model, and the thing that passes through a model is the thing
where a mistake is survivable.** Fabricating a deadline stops being possible
rather than being something we test for.

It also improves the privacy story. The cloud leg of 3b can be sent the
*extracted findings* instead of the document — a handful of field values, not a
page of someone's tax return.

---

## 6. Output contract

**[yours]** Your objection to the `SPEC.md` field table was correct: a fixed
`deadline / fee / office` schema fits a campus letter and falls apart on an EPA
label or a Schedule F. Fixed fields are the wrong shape for versatile
documents.

**[mine]** Resolution — **two tiers**, so the versatile part stays versatile
and the testable part stays testable:

**Tier 1 — universal core** (same for every document, typed, validated):

| Field | Type | Notes |
|---|---|---|
| `doc_type` | string | "EPA labeling notification", "IRS farm profit/loss form" |
| `what_it_is` | string | One sentence, plain language |
| `summary` | list[string] | 3–5 bullets |
| `urgency` | enum | see §6.1 |
| `next_steps` | list[string] | Concrete actions, no advice |
| `pages_read` | (int, int) | e.g. read 2 of 14 — surfaced in the UI, always |
| `findings` | list[Finding] | Tier 2 |
| `transcript` | string | Full verbatim OCR text |

**Tier 2 — `Finding`**, an open list the model populates per document. This is
what absorbs the variety:

| Field | Type | Notes |
|---|---|---|
| `label` | string | The model names it: "Restricted entry interval", "EPA reg. no." |
| `value` | string \| null | null when present-but-unreadable |
| `confidence` | float 0–1 | §7 |
| `quote` | string | Verbatim words this came from |
| `page` | int | **1-based page index. Required, not optional** — the click-to-jump requirement in your use-case diagram depends on it |
| `region` | bbox \| null | Where on that page — for crop escalation and highlight overlay |
| `validated` | bool \| null | Did it pass a format validator? §7.1 |
| `origin` | enum | `acroform` \| `datadetector` \| `validator` \| `model` — which tier produced it. Drives §7's green rule and the inspector. |

Why this shape: the universal core can be unit-tested and regression-tested
across every family, while `findings` never needs a schema migration when you
add a document type.

### 6.1 Urgency

**[yours]** All levels are valid; show them with icons and highlighting; my
call on specifics.

**[mine]** Three levels, assigned by **consequence**, not by days remaining —
a deadline-based rule can't grade an EPA label that has no date but does have
a legal restriction:

| Level | Means | Shown as |
|---|---|---|
| `act_now` | A dated obligation, or a legal/safety restriction currently binding | Red badge + icon |
| `soon` | An obligation with no near date, or one conditional on an action you may take | Amber badge + icon |
| `informational` | Notice, confirmation, or record — nothing required of you | Grey badge, no icon |

**Keep urgency and confidence visually distinct.** Urgency is about the
document; confidence is about our reading of it. Conflating a red urgency badge
with a red confidence ring is the easiest way to make this UI lie. Urgency =
badge + icon; confidence = ring (§7).

### 6.2 Transcript

**[yours]** Include it, in a collapsible panel.

This also buys a real test: every `Finding.quote` must be a substring of
`transcript`, so a fabricated quote fails a test instead of shipping.

---

## 7. Confidence

**[yours]** Replace discrete states with a **circular radial meter** in front
of each finding — green at high confidence, through yellow to red — with a
tooltip reading "x% confidence in reading this".

**Important caveat, and it needs a decision:** a model's self-reported
confidence is badly calibrated. If the number in that ring is just the model
saying "90%", the ring is decoration with a number painted on it — which is
worse than the discrete states it replaces, because it looks quantitative.

### 7.1 Where the number should come from

Ranked by how much they can be trusted — **now measured on all 18 scans in
`assets/scans/` (1092 text lines), not assumed:**

| Signal | Trust | Measured behaviour |
|---|---|---|
| **Format validators** | Highest | Deterministic. EPA reg numbers (`\d{3,5}-\d{2,5}`), dates, amounts, form numbers, rates+units have known shapes. `524-529` validates; `R G-2 26-O4871` does not. |
| **Vision per-line confidence — low end** | High | Real and useful. The known seal misread `"WEAL PROTEIN"` scored **0.062, the 2nd lowest of 1092 lines**. Genuine garbage clusters at the bottom. |
| **Vision per-line confidence — high end** | **Do not trust** | The four *highest*-scoring lines in the whole corpus (0.885, 0.828, 0.824, 0.788) were all `口` — checkbox artifacts read as CJK glyphs. High confidence does not mean correct. |
| **Homoglyph disagreement in `topCandidates`** | High, and specific | Caught what confidence missed: `"lan Murphy"` scored a mid-range 0.542, but candidate #2 was literally `"Ian Murphy"` — the correct reading. `l`/`I`, `O`/`0`, `rn`/`m` confusions are exactly the failure mode on reg numbers, names and dates. |
| **Raw candidate disagreement** | Low | Too noisy as a binary — 1024 of 1092 lines have *some* disagreement. Only useful filtered to homoglyph classes. |
| **Model self-report** | Lowest | Tiebreaker only, never the sole input. |

**[mine]** Two rules follow directly from the measurements, and they are not
symmetrical:

1. **Low confidence is a reliable trigger.** Below threshold → escalate. This
   works.
2. **High confidence is not a licence to show green.** A ring only reaches
   green if a format validator passed *or* the top candidates agree without a
   homoglyph substitution. Otherwise it caps at amber, whatever the OCR score.

Without rule 2 the corpus's worst garbage (`口` at 0.885) would render as the
most confident finding on the page.

The inspector (§8) shows which signals produced each ring.

---

## 8. UI surfaces

**[yours]** Two modes:

**Consumer mode** — for a normal person. No step logs, no bounds, no token
counts. Only real errors surface. Shows: what this is, summary, urgency,
findings with confidence rings, next-step checklist, collapsible transcript,
and an always-visible "read pages X–Y of N".

**Inspector mode** — a dev toggle. Shows the step log, loop bounds, raw OCR
output, per-signal confidence breakdown, which regions were escalated, what
was sent to the cloud, and the API calls made.

Worth noting: **the inspector is the better demo.** Consumer mode proves it's
usable; inspector mode proves the agent is real and not a chat wrapper. Show
both.

---

## 9. Agent loop

**[yours]** Give the agent the decision to ask or skip, the way the Claude Code
harness does — a question the user can answer or dismiss, not a blocking form.

This also resolves the problem flagged earlier: the user uploaded the document
*because they can't read it*, so asking them to read a field for us is absurd.
The two legitimate question types:

| Question type | Example | Legitimate because |
|---|---|---|
| Consent to escalate | "Two regions are unclear. Send just these crops to be read?" | Only the user can authorise it |
| Context the document cannot contain | "Is this the first notice you've had about this?" | The document genuinely doesn't say |

Never ask the user to supply a value that's printed on the page in front of us.

Skipping always proceeds — the field is marked unresolved and the result still
renders (§10).

---

## 10. Limits and failure behaviour

**[yours]** Document thresholds for size, length, format, and API errors.
**[mine]** Specifics — all of these are honest-degradation, never a dead end:

| Case | Behaviour |
|---|---|
| Pages | Read first 2 pages by default (matches `degrade.sh`). Always display "read pages 1–2 of N". Configurable. |
| File size | Reject over 20 MB with the actual size and limit in the message |
| Format | PDF first, then PNG/JPEG. **[yours]** Anything else: named rejection, not a crash |
| Not a government document | Say so plainly, don't force a schema onto it |
| Too degraded to OCR | Report that OCR failed and what to try (rescan, higher DPI) — do not emit an empty result as if it succeeded |
| Cloud escalation declined | Render everything read locally; unresolved fields marked unresolved |
| Cloud API error / timeout | Same as declined. A network failure must never lose local results |
| Model returns unparseable output | Retry once, then surface the raw OCR text — partial value beats a blank screen |

**Completeness rule** — you flagged §5 of `SPEC.md` as too narrow a framing
for government documents, and that's right. Decision: **always render what was
read.** Never withhold the explanation or the checklist because a field is
missing. Mark gaps; don't hide behind them.

---

## 11. Build order

Layers, inside out. Each one tested before the next starts.

| # | Layer | Done when |
|---|---|---|
| 1 | `ocr.swift` emits regions + confidence as JSON | Real scan → JSON with bboxes; asserted in a test |
| 2 | Format validators (EPA reg no., dates, amounts, form numbers) | Known-good and known-bad strings, table-driven test |
| 3 | Output contract types + transcript/quote substring check | Fabricated quote fails a test |
| 4 | Local extraction → `findings` | Fills tier 1 + tier 2 on the EPA fixture with no cloud call |
| 5 | Confidence composite + gate | Known-bad region scores red and is selected for escalation |
| 6 | Crop + cloud escalation + merge | Only selected crops leave; merged result marked as escalated |
| 7 | Consumer UI | The three fixtures render correctly |
| 8 | Inspector UI | Step log, signals, and escalations all visible |
| 9 | Ask/skip branch | Skip still produces a rendered result |

Layers 1–3 have no model dependency, so they're testable immediately and
independent of §12.1.

---

## 11a. Two document modes — from the use-case diagram

**[measured]** The mode is decided deterministically, with no model and no
guessing: does any page carry a `Widget` annotation?

| | Form mode | Document mode |
|---|---|---|
| Detected by | `page.annotations` contains `Widget` | it doesn't |
| Your assets | IRS 4835 (63 fields), Schedule F (89), NRCS CPA-1200 (105) | EPA labels (45 pages, 0 fields) |
| Primary output | **the fields you must fill**, each with page + rect | findings, summary, next steps |
| Extraction | PDFKit AcroForm — exact, free, no OCR | Vision OCR → §5 pipeline |
| Confidence | **not applicable** — the field list is ground truth from the file | §7 applies |

This is the strongest finding in the project so far: for born-digital
government forms, the thing your diagram calls "required fields to fill" is
**read straight out of the PDF**. Nothing to infer, nothing to hallucinate,
nothing to escalate.

### 11a.1 The one gap in form mode

Field *names* vary in quality:

- **NRCS CPA-1200** ships human-readable names — "Application Date",
  "Location where assistance is requested". Directly displayable.
- **IRS forms** ship machine names — `topmostSubform[0].Page1[0].f1_04[0]`.
  Useless to a person.

So IRS-style forms need **label resolution**: for each widget rect, find the
printed text nearest it (left, then above) from the Vision OCR pass. Both
inputs are already available, and it's geometry, not inference. This is the
only place form mode needs OCR at all.

### 11a.2 Other diagram requirements

| Requirement | Status |
|---|---|
| Click a finding → jump to its PDF page | Free. `Finding.page` + PDFKit `go(to:)`. Requires the §6 `page` field. |
| Click a highlighted area → show references beside the PDF preview | Free. PDFKit `PDFView` + overlay, split view. |
| **Export findings / todos** | **[new — conflicts]** See §12.5 |
| **Download Models** | **[new — conflicts]** See §12.1 |

---

## 12. Questions now answered by measurement

### 12.0 Summary

| Was | Now |
|---|---|
| §12.1 What runs local reasoning? | **Mostly nothing does — see below.** Apple Intelligence is disabled on this machine, but far less model work is needed than assumed. |
| §12.2 Does Vision give confidence + bboxes? | **Yes**, and more: `tables` with cells, `lists`, `detectedData`, `topCandidates`. |
| §12.4 What thresholds? | Partially — real distribution measured, and the high end turned out untrustworthy (§7.1). |

### 12.1 Local reasoning — resolved, and the answer is "need less of it"

**[measured]** `SystemLanguageModel.default.availability` on this machine
returns `unavailable(appleIntelligenceNotEnabled)`. The framework is present
and `spike_fm.swift` compiles; Apple Intelligence is simply switched off. That
is a System Settings toggle plus a multi-GB asset download, and it is
region/language gated.

But the measurements moved the goalposts. Between AcroForm (§11a), Vision
`detectedData` (`calendarEvent`, `moneyAmount`, `postalAddress`,
`measurement`) and format validators, **almost every value the product must
get right can be extracted deterministically.** What actually needs a language
model is the prose: the plain-language summary and the next-step wording.

**[mine] Recommendation — do not block on this question:**

1. Build tier 3a (deterministic extraction) now. It has no model dependency,
   no Apple Intelligence dependency, and is fully testable. Layers 1–6 of §11
   are unaffected.
2. Make tier 3b (explanation) a **swappable interface** with three
   implementations behind it: Foundation Models when available, OpenAI when
   not, and a template-only fallback that emits the findings with no prose at
   all. The template fallback means a failed model never blanks the screen.
3. Enable Apple Intelligence on the demo machine and re-run `spike_fm` before
   choosing a default. Until it runs, its quality is genuinely unknown —
   nothing here should be presented as if measured.

This also resolves the "Download Models" conflict. `architecture.md` §5 sells
"nothing to download", and your diagram has a **Download Models** use case.
Both can be true, depending on which you mean:

- **Reading it as "enable Apple Intelligence"** — the download is Apple's, the
  app just detects unavailability and links to Settings. Pitch survives intact.
- **Reading it as "fetch a GGUF and bundle llama.cpp"** — the zero-download
  pitch is gone, and per `architecture.md` §3.2 this is also what makes
  cross-platform/Tauri worth its cost. It becomes one decision, not two.

> **Needs your call:** which of those two is the box in your diagram?

### 12.2 Vision capabilities — resolved, yes

**[measured]** `doc.text.lines[]` gives `transcript`, `confidence`,
`boundingRegion`, four corner points, `isTitle`, and `topCandidates(n)`. Plus
`paragraphs`, `tables` (real `rows`/`columns`/`cell(row:col:)`), `lists`, and
`detectedData`. Measured over `assets/scans/` (18 pages, 1092 lines): 3 tables,
7 lists, 59 data-detector matches.

`detectedData` matters more than expected — `DataDetector.Match` covers
`calendarEvent`, `moneyAmount`, `postalAddress`, `measurement`,
`phoneNumber`, `emailAddress`, `link`. That is deadlines, fees, offices and
**application rates** detected natively, with bounding boxes. For EPA labels,
`measurement` is the field type the whole document is about.

### 12.3 Demo fixtures — **[yours: to be decided]**

Now that form mode exists, the natural three prove three different things: an
IRS form (form mode, exact fields, zero inference), a degraded EPA scan (OCR +
confidence + escalation), and an out-of-scope document (honest refusal).

### 12.4 Confidence thresholds — partially resolved

Distribution over 1092 real lines: min 0.054, p05 0.342, median 0.606, max
0.885, 377 distinct values. Still to pick: the escalate threshold and the
amber/red split. Do it against this corpus, and note §7.1's asymmetry — a high
score cannot be used to award green.

### 12.5 Export findings — **[new, needs a decision]**

Your diagram has **Export findings/todos**. `architecture.md` invariant **I9**
says "nothing survives the session". Export writes a file, so one of them has
to move.

The cheap reconciliation: export is **user-initiated, to a path the user
picks, containing findings and never document bytes**. I9 becomes "nothing is
persisted *without an explicit user action*", which is still a real guarantee
and still checkable. What it must not become is an app-managed history
directory, which is a different product and a different privacy claim.

> **Needs your call:** export format — Markdown checklist, CSV, or JSON?

---

### 12.6 mere.run — reconsidered, and now a live candidate

**[yours]** You raised mere.run again, and the reconsideration was warranted:
it was cut when the open question was **OCR** (where Apple Vision won on
measurement). The open question is now **local LLM inference**, which is a
different problem.

What actually argues for it — and it isn't the OCR:

> **`mere.run api serve` exposes an OpenAI-compatible `/v1/` endpoint.**

That collapses the three-implementation swappable tier in §12.1 into *one*
client with a configurable base URL: local is `localhost`, cloud is
`api.openai.com`, identical request shape. Since the cloud key is OpenAI, the
local and cloud legs of §5 become the same code path.

| | Detail |
|---|---|
| License / stack | MIT, Swift 6, MLX + vendored llama.cpp — vendorable if upstream breaks |
| macOS floor | 15+ (machine is 26.2 ✅); Linux headless too, so cross-platform stays open |
| Models | **Downloaded on demand**, `mere.run model pull` → `~/Library/Application Support/MereRun/models` |
| Maturity | 63 stars, 2 forks, 757 commits — active, small |
| Install | signed DMG, or `swift build` from source |

**Honest counterweight:** it is not strictly *safer*, it is a **different**
risk. It trades a known risk (Apple's model needs a toggle, may be too weak)
for an unmeasured one (uninstalled third-party runtime, multi-GB pull onto
**16 GB free disk**, unexercised integration). A 63-star project is not
automatically safer than a first-party Apple framework — but it is more
*controllable*, which may matter more.

**[mine] If adopted: reasoning tier only. Keep `ocr.swift`.** Apple Vision is
measured working, needs no install and no download, and supplies the per-line
`confidence`, bboxes, `tables` and `detectedData` the whole escalation gate
(§5, §7) is built on. mere.run's OCR would need a model pull to deliver less.

### 12.7 The comparison harness — built, ready to run

**[yours]** You chose to measure Apple's model before paying mere.run's cost.
The harness exists so both candidates are scored identically:

| Path | Purpose |
|---|---|
| `eval/cases.json` | Ground truth for two real EPA letters. Every value read off actual OCR output — nothing invented. |
| `eval/score.py` | One scorer, any model. Reads the answer on stdin. |
| `eval/openai_run.py` | Runner for any OpenAI-compatible endpoint — **serves both mere.run and OpenAI**. stdlib only. |
| `spike_fm` | Runner for Apple Foundation Models. Diagnostics on stderr, answer on stdout, so it pipes into the same scorer. |

The two cases are deliberately opposed: `epa-524-529` requires **nothing** of
the recipient, `epa-7969-242` carries a real obligation **plus** a relative
deadline ("18 months from the date of this letter") anchored against a decoy
date ("Application Date: October 22, 2015"). A model that invents obligations
fails the first; one that misses them fails the second; one that anchors the
arithmetic to the decoy fails the trap explicitly, with the reason printed.

**[verified]** Scorer self-checked against a hand-written good answer (12/12)
and a hand-written dangerous answer (10/12, failing `trap:wrong_deadline_anchor`
on "April 2017"). It discriminates.

Run once Apple Intelligence is on:

```sh
./ocr assets/scans/007969-00242-20170111-01.jpg | ./spike_fm | \
    .venv/bin/python eval/score.py epa-7969-242
```

---

## 13. Still open — needs your decision

| # | Question | Why it blocks |
|---|---|---|
| 1 | **"Download Models"** — enable Apple Intelligence, or bundle llama.cpp + a GGUF? (§12.1) | Decides the zero-download pitch, and couples to native-vs-Tauri |
| 2 | **Export format** — Markdown checklist, CSV, or JSON? (§12.5) | Small, but it changes invariant I9 |
| 3 | **Demo fixtures** — the three, and what each proves (§12.3) | Suggestion recorded; your call |
| 4 | **Confidence thresholds** — escalate point, amber/red split (§12.4) | Measure against `assets/scans/`, don't guess |
| 5 | **Page window** — the EPA label is **45 pages**; "first 2 pages" (§10) will miss the rates entirely | Needs a real answer for long documents |

## 14. Decision log

| § | Decision | Source |
|---|---|---|
| 1 | Renamed: Government Document Reader | yours |
| 1 | Government docs + complex documentation, samples in `assets/` | yours |
| 1.4/5 | Hybrid: local first, escalate only low-confidence crops, with consent | yours |
| 2 | **Start clean** — do not fork the Field Log skeleton | yours |
| 3.1 | PDF and document formats first; **no camera capture** in MVP | yours |
| 4.1 | Fixed field schema rejected as too rigid for varied documents | yours |
| 4.2 | Urgency: all levels valid, icons + highlighting | yours |
| 4.3 | Include transcript, collapsible | yours |
| 5 | `SPEC.md` completeness framing too narrow for gov docs | yours |
| 6 | Confidence as a radial ring with % tooltip, not discrete states | yours |
| 7.1 | No step log for consumers; dev inspector mode instead | yours |
| 7.2 | Ask-or-skip, like the Claude Code harness | yours |
| 8 | Document thresholds for size/length/format/API error | yours |
| 9 | Done = fully parsed, then results shown with progress | yours |
| — | Cloud provider: OpenAI key | yours |
| 3 | Two families tuned, third degrades honestly | mine |
| 4 | Non-goals list | mine |
| 6 | Two-tier output contract (core + open findings) | mine |
| 6.1 | Consequence-based urgency; urgency and confidence kept visually distinct | mine |
| 7.1 | Confidence composite, format validators weighted highest | mine |
| 10 | Page/size/format limits and degradation behaviour | mine |
| 11 | Build order | mine |

---

## 15. Repo state

Superseded by your work, safe to delete:

| Path | Why |
|---|---|
| `spike.py` | Written before the spec existed; assumes `claude-opus-5` (cloud-first) and a fixed schema. Both now void. |
| `fixtures/` | Synthetic letters. `assets/` + `degrade.sh` are real documents, degraded realistically — strictly better. |
| `agent.py`, `app.py`, `index.html` | Field Log prototype. "Start clean" decided in §2. Worth reading once for the bounded-loop and evidence-quote patterns before deleting. |

Keep: `assets/`, `degrade.sh`, `ocr.swift`, `ocr`, `SPEC.md` (as the review
record), this file.

One correction to carry forward: an earlier note in this project recorded
mere.run as "cut, no OCR needed." The cut stands, but the reason has changed —
`ocr.swift` (Apple Vision) is the local OCR tier, and OCR is now central to the
design rather than unnecessary.
