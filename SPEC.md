# Letter Explainer — Spec

Status: **decisions open**. Fill in each `**Decision:**` line. Options and
tradeoffs are listed to choose from, not to be accepted by default.

---

## 1. Scope

### 1.1 Document lane

Your planning doc picked campus/admin letters. Confirm or change.

- **Campus/admin** — easy to source, low legal risk, judges understand it
- **Newcomer/settlement** — stronger impact story, accuracy matters more
- **Civic/municipal** — broadly understandable, public-service framing

> **Decision:** _____

### 1.2 Document types inside that lane

How many distinct letter types must work live? Each one added is another
demo fixture and another way to fail on stage.

> **Decision:** _____

### 1.3 Non-goals

Things you will say "no" to if you think of them at hour 14. Write them down
now, while it's cheap.

> **Decision:** _____

### 1.4 Where processing happens — decide this first

This one cascades into §2, §3, §4 and the model choice, so it is not a
detail. A background agent drafted a privacy-first framing ("processed
entirely by local models, so a document full of your personal details never
leaves your machine"). That contradicts the earlier decision in this project
to cut `mere.run` and build on `claude-opus-5`, which is a cloud API. Both
positions are defensible; they are not compatible.

- **Cloud (`claude-opus-5`)** — native PDF/image reading, no OCR step, one
  API call returns the whole schema. Fastest path to a working demo. The
  pitch cannot claim privacy, and the demo needs network on stage.
- **Local (`mere.run` or similar)** — the privacy claim becomes true and
  becomes the strongest part of the story: the documents people least want to
  upload are the ones they most need read. Costs a Swift runtime install
  (not currently on this machine), an OCR step, a separate extraction model,
  and unknown quality on real letters. Largest risk in a 24h build.
- **Hybrid** — local OCR/redaction, cloud reasoning. Honest only if you are
  precise about what leaves the machine; a redaction step you cannot verify
  is worse than no privacy claim.

If this lands on local or hybrid, the OCR spike moves to the front of the
queue and the earlier "no OCR needed" finding is void.

> **Decision:** _____

---

## 2. Base

Fork the existing Field Log skeleton, or start clean?

- **Fork it** — bounded loop, evidence quotes, uncertainty flags, stateless
  server, and an assert-based self-check already exist and work. You inherit
  its shape whether or not it fits.
- **Start clean** — no inherited assumptions, but you rewrite the loop,
  the server, and the honesty machinery from zero.

> **Decision:** _____

---

## 3. Input

### 3.1 Accepted formats

PNG/JPEG, PDF, or both. Claude reads both natively as content blocks —
**unverified in this project, no API key yet.**

> **Decision:** _____

### 3.2 Size and page limits

What do you reject rather than attempt? (Multi-page PDF? 12MB phone photo?)

> **Decision:** _____

### 3.3 Camera capture

In or out for the MVP?

> **Decision:** _____

---

## 4. Output contract

The core types. This is the spec's centre — everything else follows from it.

### 4.1 Fields

For each field: name, type, nullable?, and **what makes it correct**.
Candidates from your planning doc:

| Field | Type | Null OK? | What "correct" means |
|---|---|---|---|
| doc_type | | | |
| summary | | | |
| urgency | | | |
| deadline | | | |
| office / location | | | |
| required documents | | | |
| appointment | | | |
| fee | | | |
| next_steps | | | |
| sources (evidence quotes) | | | |

> **Decision:** _____

### 4.2 Urgency

What are the levels, and what rule assigns them? "Urgent" has to mean
something checkable, not a vibe.

- Days-until-deadline thresholds
- Consequence-based (money/access at stake vs. informational)
- Model's judgement, unconstrained

> **Decision:** _____

### 4.3 Verbatim transcription

Include a full transcription of the document in the output, or not?

- **Include** — makes every evidence quote machine-checkable (substring
  test), so a fabricated quote fails a test instead of shipping. Costs
  output tokens and shares the `max_tokens` budget with thinking.
- **Omit** — cheaper, but "source evidence" becomes unfalsifiable.

> **Decision:** _____

---

## 5. Completeness rule

Field Log refuses to emit a CSV row while any required field is blank. A
letter has no equivalent — a letter with no fee is a perfectly good letter.
So: **when is the agent allowed to show a plan?**

- **Always emit, mark the gaps** — most useful to a real person, weakest
  guardrail story
- **Withhold the whole plan unless deadline + action are known** — strongest
  guardrail story, risks refusing on letters that are actually fine
- **Emit the explanation, withhold only the checklist when the action is
  unknown** — middle path, more logic to get right

> **Decision:** _____

Which fields (if any) are load-bearing enough that their absence changes
what the user is shown?

> **Decision:** _____

---

## 6. Uncertainty states

Field Log has two states: read, or guessed. A scanned letter needs more.

- **2 states** — guessed / missing
- **3 states** — guessed (inferred) / unreadable (visible but not legible) /
  missing (not in the document)

Three is more honest and more demo-able; it's also a state you have to
handle everywhere in the UI.

> **Decision:** _____

How does each state render for the user?

> **Decision:** _____

---

## 7. Agent loop

### 7.1 Bounds

Max steps, max clarification rounds. Both shown on screen?

> **Decision:** _____

### 7.2 The clarification branch

The Field Log port breaks here: a farmer knows the answer to "what was the
rate?", but your user uploaded the letter *because they can't read it*.
Asking them for the deadline is asking them for the thing they came for.

- **Ask only about things the letter cannot contain** — earlier notices
  received, which campus, whether they already submitted something
- **Ask the user to confirm a low-confidence read** — "I think this says
  March 6, can you check?" (honest, but it's verification, not clarification)
- **No clarification branch** — single-shot. Simpler; gives up the
  multi-turn agent-design point.

> **Decision:** _____

### 7.3 Observable steps

What exactly does the step log show a judge? Name the steps.

> **Decision:** _____

---

## 8. Failure and refusal

| Case | Behaviour |
|---|---|
| Not a letter at all | |
| A letter, but outside the chosen lane | |
| Unreadable image (too blurry to transcribe) | |
| API error / timeout | |
| Model returns unparseable output | |

> **Decision:** _____

---

## 9. Done criteria

What must be true for this to be finished? Each one has to be checkable by
running something, not by looking at it and feeling good.

> **Decision:** _____

### 9.1 Demo fixtures

Which letters, and what does each one prove?

| Fixture | Proves |
|---|---|
| | |
| | |
| | |

> **Decision:** _____

---

## 10. Open questions

Things you don't know yet and need to find out — and how you'd find out.

> **Decision:** _____
