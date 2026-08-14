# AI Workflow Rules — Government Document Reader

How an AI agent works in this repo. *How* code is written: `coding-standards.md`.
Product: `context/project-overview.md`. Stack, boundaries and invariants:
`context/architecture.md`. Status: `context/progress-tracker.md`.

Same test as the coding standards: every rule here is checkable by a diff.

**Active feature spec** = the one row of the **Build order** table in
`context/progress-tracker.md` currently marked `in progress`, together with the
sections of `context/` that row names. There is never more than one.

---

## 1. One unit at a time

Implement only the feature in the active spec. One build-order row. Finish it,
then stop and report.

Not allowed in the same run: the next row, a related feature that "fits
naturally", a roadmap item, scaffolding for later, a helper nothing yet calls.
If you notice one, write it down in the report — don't build it.

Finished means the row's own **Done when** column is satisfied by a test that
was run. Code that looks right is not finished.

Rows are ordered inside-out; each is tested before the next starts. Starting row
5 while row 3 is `not started` is out of order — say so, don't do it.

If the unit turns out bigger than its row implies, propose a split into new rows
and get it agreed before writing code (§3).

## 2. Never break invariants

Read `context/architecture.md` before generating any code — §6 boundaries, §7
storage model, §8 invariants **I1–I13**, §11 output contract, §12 confidence
composite. Then `coding-standards.md` §1 for the layer table.

These are not style preferences. Each is enforceable by a test:

- **I1** — document bytes leave only through the single egress function, and only
  for crops the user approved.
- **I2** — every rendered value quotes a verbatim substring of the transcript.
- **I3** — a finding failing its format validator can never render green.
- **I6 / I11** — the local result survives any cloud failure or skip.
- **I7 / I9** — the source file is never modified; nothing persists past the session.
- **I12** — one coordinate origin, converted once at Boundary A.
- Imports point down only. A file's layer is its directory.
- `coding-standards.md` §5.2 — no document text, crop bytes, filename, path or
  key ever reaches a log.

Code that would weaken an invariant is not written and then flagged. It is
stopped at §3.

## 3. Ask before assuming

Stop and ask when the spec is ambiguous, contradicts another context file, or
needs an architectural decision `context/` doesn't already contain — a new
dependency, an engine or endpoint swap, a contract change, a new layer or
boundary, or anything touching the **Open — needs a decision** table.

Ask with: what's ambiguous, the readings you see, which you'd pick, and why.
Then wait. Do not guess intent and do not proceed on the assumption that a
guess can be corrected later.

Routine judgement calls inside a row — a variable name, a test's fixture — are
yours. The line is whether a different answer changes the architecture.

## 4. Update the progress tracker

Status vocabulary in the Build order table: `not started` → `in progress` →
`complete`. A parenthetical note may follow. Rows still carrying free-text status
from before this file existed get normalised the first time they are touched.

**Before writing any code:** read the active spec, then set that row to
`in progress` and rewrite **Current phase** to match. This is the first edit of
the session, and it is what makes "one unit" visible to anyone else reading.

**When the unit is complete and every checklist item in §7 passes:** set the row
to `complete`. Also, where it applies:

1. **Decision log** — one row per decision, tagged *yours*, *mine*, or *measurement*.
2. **What measurement settled** — any number produced, with how it was produced.
   A number that only exists in terminal scrollback is lost.
3. **Open — needs a decision** — delete what this unit answered, add what it opened.
4. **`context/architecture.md`** — if the stack, boundaries, storage model or
   invariants changed (`coding-standards.md` §7), with the tracker pointing at it.

The tracker edit ships in the same commit as the code. A commit that moves code
without moving the tracker is incomplete.

## 5. No destructive refactors

Do not refactor working code unless the spec asks for it. Not renames, not
reorganisation, not "while I was in there".

Allowed without asking: the change the row requires, and deleting a file the
tracker's **Repo state** table already lists as superseded.

If working code genuinely blocks the row, that's a §3 stop — describe the block
and the smallest change that clears it, then wait.

## 6. Use agent skills

Before writing logic against a third-party library or framework, consult the
installed skill for it rather than recalling its API. Skills are current; memory
is not.

Applies here to Apple Vision / PDFKit / Foundation Models, any OpenAI-compatible
client, and anything added later. Anthropic or Claude APIs → the `claude-api`
skill, always, before opening the file. If no skill covers the library, read its
actual headers or docs in this repo's `.venv`/SDK and cite what you read.

Verify the API exists before depending on it. `context/architecture.md` marks
checked facts **[verified in SDK]** — match that bar or mark the claim unverified.

## 7. Checklist

- [ ] Exactly one build-order row touched; it was `in progress` before code was written.
- [ ] That row's **Done when** is satisfied by a test that was actually run.
- [ ] Failing test came first, and its failure message was read.
- [ ] No invariant weakened; §2 list re-read against the diff.
- [ ] Nothing implemented that the row didn't ask for.
- [ ] No working code refactored that the spec didn't name.
- [ ] Third-party APIs taken from a skill or verified source, not memory.
- [ ] Ambiguities raised as questions, not resolved by guess.
- [ ] Row set to `complete`; tracker and `architecture.md` updated per §4, same commit.
- [ ] `coding-standards.md` §8 checklist passes.

## 8. Reporting

At the end of a unit: the row, the command that proves it and its **actual
output**, what changed in `context/`, anything deliberately not built, and what
must be decided before the next row starts.

Never report a unit complete without having run its check in the same session.
