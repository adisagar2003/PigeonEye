# Project Overview — Government Document Reader

What the product is, who it serves, and what it will not do.
Tech stack and boundaries: `context/architecture.md`.
Status, decisions, and open questions: `context/progress-tracker.md`.

---

## 1. The product

Photograph or import a confusing government document and get back a
plain-language explanation, the obligations and deadlines that actually matter,
and a checklist of what to do next — read on your own machine, with every claim
quoted from the source and every uncertain reading marked as uncertain.

## 2. Who it's for

Someone who receives or must comply with an official document and cannot tell
what it obligates them to do. The failure they're avoiding isn't confusion — it's
missing one line and losing money, access, or legal standing.

Concretely, a farmer or farm operator: EPA pesticide labels, IRS farm tax forms,
NRCS conservation paperwork.

## 3. Why it isn't a summariser

Two properties, both load-bearing:

1. **Nothing leaves the machine unless you say so.** The documents people least
   want to upload are the ones they most need read. When a region is too unclear
   to read locally, the app shows you the exact crop it would send and asks.
   Declining still produces a result.
2. **It tells you where it's unsure.** A confident wrong date on a regulatory
   document is worse than no date. Every value carries a confidence reading and
   the verbatim words it came from.

### 3.1 Which configuration you're running

Property 1 is a claim about the **local configuration**, and that configuration
is the product. On a machine with a local reasoning model, nothing leaves —
full stop.

On a machine without one, the app falls back to a configured OpenAI-compatible
endpoint. This is the demo machine's situation today: Apple Intelligence is off,
so the fallback is what the demo runs on.

**The user is told which one they're in, at import, before anything is read.**
Not in settings, not in a tooltip — on the screen where the document lands. A
fallback the user has to discover is the same as a lie.

## 4. Core user flow

The flow has two shapes, and **which one runs is decided by the reasoning tier,
not by a setting the user hunts for.**

**Local tier — the crop gate is live:**

```
import PDF  →  read it locally  →  results
                     │
                     └─ region too unclear?
                            → show the exact crop, ask to send it
                            → allow: send just that crop, merge the answer
                            → skip:  mark it unresolved, keep going
```

**Cloud tier — no per-crop gate:**

```
import PDF  →  "this document is read using <endpoint>"  →  read  →  results
                     │
                     └─ region too unclear?
                            → send the crop, merge the answer, mark it escalated
```

### 4.1 Why the gate disappears when the tier is cloud

Because it would be theatre. If the reasoning tier is an OpenAI-compatible
endpoint, the document's text is already going there to be summarised. Stopping
to ask permission for a 200×80 crop of a page whose full transcript was sent a
second earlier does not protect anything — it performs protection, which is
worse than not having the gate, because the user reads the prompt as evidence
that everything *else* stayed home.

So the conditional is on the tier, not the confidence:

| Reasoning tier | Low-confidence region |
|---|---|
| **Local** | Show the exact crop. Ask. Allow → send only that crop. Skip → mark unresolved. |
| **Cloud** | Escalate inside the consent already given at import. No second prompt. |

Two things this does **not** change:

- **Consent still exists** — it moved to import time, where it now covers the
  honest scope ("this document will be read using X") instead of a narrow one.
- **Escalations are still visible.** Every escalated value is marked as escalated
  in the result, and inspector mode still shows exactly what was sent where. The
  prompt is gone; the disclosure is not.

The default path never touches the network. Escalation is an exception the user
authorises per document, not a mode or a setting.

## 5. What the user gets back

| | |
|---|---|
| What this is | one plain sentence naming the document type |
| Summary | 3–5 bullets |
| Urgency | `act now` / `soon` / `informational` — badge + icon |
| Findings | the values that matter, each with a confidence ring, the quote it came from, and a click-to-jump page reference |
| Next steps | concrete actions, never advice |
| Pages read | "read pages 1–2 of 14", always visible, never hidden behind a disclosure |
| Transcript | the full text it read, collapsible |

Urgency is about the document; confidence is about our reading of it. They never
share a visual language — badge for one, ring for the other.

Two modes: **consumer** (the above, no logs, no internals) and **inspector** (a
dev toggle showing the step log, per-signal confidence breakdown, and exactly
what was sent where). Consumer mode proves it's usable; inspector mode proves
the agent is real.

## 6. Two document modes

The mode is decided by the file, not by a guess: does any page carry a fillable
form field?

| | Form mode | Document mode |
|---|---|---|
| Example | IRS 4835, Schedule F, NRCS CPA-1200 | EPA labels |
| Primary output | **the fields you must fill**, exact, read straight out of the file | findings, summary, next steps |
| Confidence | not applicable — the field list is ground truth | applies |

For born-digital government forms there is nothing to infer and nothing to
hallucinate. That is the strongest thing this product has.

## 7. Scope

Samples live in `assets/`. Two families work properly, a third degrades honestly,
and a fourth exists only to test scale:

| Family | Files | Role |
|---|---|---|
| EPA pesticide labels | 6 PDFs in `assets/epa-labels/` | **Primary.** Dense, legally binding — application rates, restricted-entry intervals, PPE. Real consequences for misreading. |
| IRS farm tax forms | Schedule F, 4835 in `assets/gov-forms/` | **Secondary.** Proves structured forms and two-column layouts, not just prose. |
| NRCS conservation application | CPA-1200 in `assets/gov-forms/` | **Untuned.** If it works, bonus. If it half-works, that *is* the honesty demo. |
| Long IRS publications | P17 (142pp), P946 (113pp), P225 (99pp) in `assets/long-docs/` | **Scale.** Everything else is ≤45 pages; these are the only inputs that say whether paging, indexing and memory hold at 100+ pages. |

`assets/scans/` holds the same pages deliberately degraded, to force the OCR
path. `assets/golden/` holds public labelled datasets used to check the pipeline
generalises beyond documents it was tuned on — evaluation only, not new scope;
see `assets/golden/README.md`.

## 8. Out of scope

| Non-goal | Why |
|---|---|
| Filing, submitting, or sending anything | One irreversible action ruins the trust story |
| Legal, tax, or compliance advice | It explains documents; it does not tell you your obligations are met |
| Accounts, login, persistence across sessions | No product value in 24h, and it contradicts the privacy pitch |
| Document types outside §7 | Unbounded scope, unbounded failure |
| Camera capture | File import only for MVP |
| Editing or annotating the source PDF | Different product |
| Fine-tuning or training anything | Not a 24h activity |
| Browser automation, RAG over regulation corpora, multi-agent orchestration | Ruled out, staying ruled out |

Export of findings is the one write the app performs: user-initiated, to a path
the user picks, containing findings and never document bytes.

## 9. When it can't read something

Every case renders what *was* read. None is a dead end.

| Case | Behaviour |
|---|---|
| File too large (>20 MB) | Reject, naming the actual size and the limit |
| Unsupported format | Named rejection, not a crash |
| Not a government document | Say so plainly; don't force a schema onto it |
| Too degraded to OCR | Report that OCR failed and what to try — never an empty result dressed as success |
| Escalation declined, or the cloud errors | Local results stand; unresolved fields marked unresolved |
| Model output unusable | Retry once, then show the raw text — partial beats blank |

**Completeness rule:** never withhold the explanation or the checklist because a
field is missing. Mark gaps; don't hide behind them.

## 10. Done, for the demo

Three fixtures, each proving a different thing:

1. **A form** — exact fields, zero inference.
2. **A degraded EPA scan** — OCR, confidence, and a consented escalation.
3. **An out-of-scope document** — honest refusal.
