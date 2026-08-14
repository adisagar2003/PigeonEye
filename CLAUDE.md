# CLAUDE.md — Government Document Reader

Read this first, then the file the task points at. Nothing here is duplicated
from `context/` — this is the index, `context/` is the source of truth.

## Where things live

| File | Answers |
|---|---|
| `context/project-overview.md` | What the product is, who it's for, what it will **not** do |
| `context/architecture.md` | Stack, boundaries (§6), storage model (§7), **invariants I1–I13** (§8), output contract (§11), confidence composite (§12) |
| `context/progress-tracker.md` | Current phase, build order, what measurement settled, open decisions, decision log, repo state |
| `coding-standards.md` | How code is written — layers (§1), naming (§2–3), TDD (§4), observability (§5), context updates (§7), review checklist (§8) |
| `ai-workflow.md` | How an agent works here — one build-order row at a time, ask before assuming, tracker updated per unit |

`context/` is the single source of truth for *why*. A change that alters the why
without changing `context/` is incomplete (`coding-standards.md` §7).

## Before writing any code

1. Read `ai-workflow.md`. It governs scope, questions, and tracker updates.
2. Read the **Build order** table in `context/progress-tracker.md` and work
   exactly one row. Set it to `in progress` first.
3. Read `context/architecture.md` §8 and check the change against every
   invariant it touches.
4. Write the failing test first (`coding-standards.md` §4).

## The constraints that are not negotiable

- **One unit at a time.** One build-order row, finished and tested, then stop.
- **Invariants hold.** I1 single egress for approved crops only · I2 every value
  quotes a verbatim substring · I3 validator failure can never render green ·
  I6/I11 local result survives any cloud failure or skip · I7/I9 source never
  modified, nothing persists · I12 one coordinate origin.
- **Imports point down only.** A file's layer is its directory
  (`coding-standards.md` §1).
- **Logs are allowlisted.** No document text, crop bytes, filename, path or key
  (`coding-standards.md` §5.2).
- **Ask, don't guess.** Ambiguity, contradiction, or a decision `context/`
  doesn't contain → stop and ask (`ai-workflow.md` §3).
- **No unrequested refactors.** Working code stays unless the row names it.

## Repo

Swift for the tool and UI layers, Python for evaluation. `ocr.swift` → `ocr` is
the measured local OCR tier. `eval/` scores any engine or model against real
ground truth. Superseded files are listed under **Repo state** in the tracker —
delete them, don't extend them.

Build the OCR binary with `swiftc -O ocr.swift -o ocr`.
