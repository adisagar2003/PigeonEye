# F4 · Explain it

**The user can** open a government document and read, in plain language, what it
is, what it obligates them to do, and what happens if they ignore it.

Product · `../project-overview.md` §5, §4.1 (consent) ·
Boundaries and invariants · `../architecture.md` §6, §8 (**I1**, **I6**, **I10**,
**I13**), §11, §12 · Status · `../progress-tracker.md` ·
Slices · `../../issues.md` F4

**Precedence.** Where this file and `context/` disagree, `context/` wins.

---

## 1. Demo

Open `assets/epa-labels/007969-00242-20170111.pdf`. The rail says what it is
immediately — assembled locally, no model, no network. Press **Explain with
OpenAI** and the same panel is replaced by the model's reading, in bold, under a
cyberbrain and the provider's name.

Measured on `066330-00424-20181218.pdf`: the model returned the label amendment,
the products added, the obligation to submit final printed labelling, and
*"18 months from December 18, 2018"* — anchored to the letter's own date, which
is the trap `eval/cases.json` calls `wrong_deadline_anchor`.

---

## 2. This slice created layer 3

Before it, the no-egress claim was **the absence of an API** — `rg 'URLSession'
Sources` returning empty. That was a stronger guarantee than any check, and it is
now gone. What replaces it:

- **One file.** `Sources/Gate/Gate.swift` is the only place `URLSession` appears,
  and `scripts/layers.sh` fails the build if that stops being true. It caught a
  `URLSession` default *argument* in layer 4 during this slice — the invariant
  earning its keep on the day it was written.
- **Agent does not depend on Gate**, and must not. `Package.swift` enforces it.
  An agent that opens a socket is a bug against **I1**, not a style issue.
- **UI is the only layer that sees both**, which is why the additive-only
  fallback lives there rather than inside a view.

### What crosses, and what never does

| Crosses | Never crosses |
|---|---|
| The transcript text | The source file's bytes |
| Recognised values and their quotes | The filename, the path |
| — | Any page image or crop |
| — | The key, anywhere but the `Authorization` header |

---

## 3. Contract

| Layer | Holds |
|---|---|
| 0 `Contracts` | `Explanation` — docType, whatItIs, summary, urgency, nextSteps, **source**, **provider**, **signals**, note |
| 2 `Agent` | `explain(_:)` — 4.1, deterministic, zero model calls. `explanationSignals(_:)` |
| 3 `Gate` | `Gate.explain(…)` — the single egress function, injectable transport |
| 4 `UI` | `explained(_:config:transport:)` — the additive-only fallback; the panel |

### 3.1 4.1 exists so that 4.2 is allowed to fail

The local explanation is **not** a fallback bolted on afterwards; it is the thing
the cloud leg is additive *to*. **I6** says the local result survives any cloud
failure, and the only way to mean that is for it to exist first and stand alone.
It renders the moment a document is read, before anything has been offered the
chance to leave.

### 3.2 The consent moment

Cloud tier takes the grant for the whole document rather than per crop
(`project-overview.md` §4.1). Here that grant is **the button press**: nothing is
sent on open, the button states what leaves before it is pressed, and with no key
configured there is no button at all — only the reason there isn't one.

### 3.3 I13 is asserted against the bytes that go out

The 45-page label is ~32,000 tokens against a ceiling that fails *silently*.
Budgeting the prompt alone leaves the JSON envelope unaccounted for, which is how
a request lands 41 tokens over — the first version of this did exactly that and a
test caught it. The estimate now runs on the serialised body, in at most three
corrective passes (**I10** — bounded, never a `while true`), and any cut is
**said out loud** in the panel.

### 3.4 The ring over a summary rates the reading, not the writing

A confidence for a model's prose cannot be the model's own self-report — **I4**
forbids exactly that. The admissible non-model signal is the **mean per-line
recognition confidence of the pages the summary was built from**: a fluent
paragraph written from a badly OCR'd page is confidently wrong, and that is the
failure this product exists to catch.

The model's self-rating is requested and carried as a `model` signal so the
inspector can show it, and it is never sufficient to produce a band. The panel
says so in words, because a ring beside prose invites the wrong reading of what
was measured.

---

## 4. TDD flow

| # | Red — write this test first | The failure you should read | Green |
|---|---|---|---|
| 1 | `a_document_with_nothing_found_still_explains_itself` | `cannot find 'explain' in scope` | `Agent/Explain.swift`, no model anywhere |
| 2 | `a_form_is_explained_as_a_form_and_counts_its_fields` | — | the field count is the headline for a form |
| 3 | `no_key_means_no_configuration_and_no_call` | `cannot find 'Gate'` | layer 3, and `Config?` so the UI can decline to offer |
| 4 | `the_payload_never_carries_the_filename_or_the_path` | — | **I1**, asserted on the actual request body |
| 5 | `the_key_travels_in_the_header_only` | — | never in the body, never in a log |
| 6 | `an_oversized_transcript_is_cut_before_sending_and_says_so` | `12041 <= 12000` — the envelope was not counted | measure the serialised body, cut, repeat ≤3× |
| 7 | `a_cloud_failure_falls_back_to_the_local_explanation` (401/429/500/503) | — | **I6**, additive-only |
| 8 | `an_unreachable_endpoint_falls_back_too` · `a_garbled_reply_falls_back_too` | — | offline, and valid-HTTP-wrong-shape |
| 9 | `a_good_reply_replaces_the_local_explanation` | — | so the fallback tests are not green for the wrong reason |

No test here touches the network: the transport is injected.

---

## 5. Acceptance criteria

- [x] Doc type, summary, urgency and next steps assembled with **zero** model calls (4.1)
- [x] One OpenAI-compatible client, swappable base URL (`OPENAI_BASE_URL`, `OPENAI_MODEL`)
- [x] Any failure falls back to 4.1 — tested across 401/429/500/503, offline, and a garbled reply
- [x] Nothing is sent without an explicit press; no key means no button
- [x] Token budget asserted **before** the call, truncation said out loud (**I13**)
- [x] The summary carries a confidence built from a non-model signal (**I4**)
- [x] `sh scripts/layers.sh` — `URLSession` appears only under `Sources/Gate`

---

## 6. Stress test

| Case | Must happen |
|---|---|
| **A 45-page document** | Cut to fit, and the cut is stated in the panel. A silent truncation reads as "it read all of it". **Tested**, and seen on a 22-page label in the running app. |
| **No key** | No button, and a sentence saying why. A button that cannot work is worse than no button. **Tested** at the config level. |
| **401 / 429 / 500 / 503 / offline / garbled** | The local reading stays on screen with the reason attached. **Tested**, six ways. |
| **A second document opened mid-request** | The answer to the older request is discarded — the same generation check every other `await` in `ReaderModel` uses. |
| The model rating itself highly on a badly-read page | The ring still reflects the OCR quality, because the model's self-report can never produce a band alone (**I4**). |

---

## 7. Out of scope

Slice **4.3** (measure a local reasoning tier) — open, and no longer a gate: the
first iteration is cloud-only by decision, and a local tier is an option behind
the same base URL. F5's crop-level escalation, F6's honest refusals, F8's export.

**Known ceilings, carried:** the token estimate is a character count rather than
a tokeniser, erring toward sending less than allowed; and the request is a single
call rather than the map-reduce over paragraphs/tables/lists that `issues.md` 4.2
describes, so a long document is truncated rather than chunked.
