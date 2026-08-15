# F9 · Ask about this page

**The user can** type a question about the page in front of them and get an
answer grounded on that page — with the model allowed to go and read a page it
was never shown, and with exactly what left the machine listed afterwards.

Product · `../project-overview.md` §3.1 (which tier you are in), §4.1 (why the
grant is per document), §9 (never a dead end) ·
Contract and invariants · `../architecture.md` §6 (Boundary **Q**, §6.1 why
layer 3 costs something), §7 (storage), §8.0 (**I1**, **I2**, **I9** under F9),
§8 (**I6**, **I10**, **I13**) ·
Status · `../progress-tracker.md` ·
How code gets written · `../coding-standards.md` ·
Agent rules · `../../ai-workflow.md` ·
Slices · `../../issues.md` F9

**Precedence.** Where this file and `context/` disagree, `context/` wins.

**Written after the code, not before it** — against `coding-standards.md` §4 and
`ai-workflow.md`. The feature was built on request from a conversation rather
than from a row in the build order, and the spec is the debt that ordering
bought. It is written from the diff that shipped, so §6 and §7 describe what the
tests actually assert rather than what someone hoped they would.

---

## 1. Demo

Open `assets/epa-labels/000524-00529-20241120.pdf` — 45 pages, the flagship
label. Page to 12 and ask *"what is the restricted-entry interval here?"*. The
panel asks once whether page text may go to the endpoint, you agree, and the
answer comes back naming page 12.

Then ask *"where are the woody-brush rates?"*. They are **not on page 12** —
they are on page 34, the rate table nobody has scrolled to. The model calls
`read_page(34)`, answers from it, and the answer is stamped `from page 12,
page 34`. Open the inspector: two lines, one per page that left, each naming
the page, its size and the host. Neither line contains a word of the document.

That second question is the feature. The first one a transcript could have
answered.

**Then switch the tier to "On this Mac" and ask the first question again.** The
same answer arrives, the consent card never appears, and the inspector still
says *Left this machine: nothing* — because this time it did not. That is
`project-overview.md` §3's headline claim, on screen, with the feature still
working rather than switched off.

---

## 2. Settled before writing this

| Question | Answer | Whose |
|---|---|---|
| Grounded on the page, or on the document? | **The page.** Sending all 45 pages on every question makes "this page's text is sent" a sentence the app cannot mean | yours |
| May the model see pages it was not given? | **Yes, through one tool**, bounded. A reader who already knew which page to turn to would not be asking | yours |
| How is consent taken? | **Once per document**, in the panel, before the first question — the same shape as the import-time grant. On the on-device tier, **not at all**, because nothing leaves | yours, per `project-overview.md` §4.1 |
| Is there an on-device tier? | **Yes, and it is preferred when available.** Half the product's pitch was a disabled button without it | yours, from review |
| Does an answer become a `Finding`? | **No.** See §5 | mine |
| Which endpoint? | Any OpenAI-compatible `/v1`, base URL from the environment. Cloud for the demo | `progress-tracker.md`, "Agent is model-agnostic" |
| Where does the loop live? | Layer 4 — and not by preference. See §3.2 | `coding-standards.md` §1 |

---

## 3. Contract

### 3.1 What each layer holds

| Layer | Target | Holds |
|---|---|---|
| 0 | `Contracts` | `Turn`, `Call` (with `Call.requestedPage`), `Limits.askHops` / `askPages` / `askPageChars` / `askHistory` / `askQuoteChars` / `askQuestionChars` / `maxPromptTokens` / `localPromptTokens` |
| 2 | `Agent` | `Ask.swift` — how a question is grounded on a page, shared by both tiers, pure. `LocalModel.swift` — the on-device tier and its availability |
| 3 | `Gate` | `Gate.Config`, `Gate.Transport`, `Gate.Reply`, `Gate.answer(…)` — one POST, one tool offered, nothing else |
| 4 | `UI` | `answered(…)` — the cloud hop loop; `answeredHere(…)` — the local adapter; `ReaderModel` state; the `askBlock` panel and the consent card |

**The prompt builders are in layer 2 because there are two callers and one
fact.** Both tiers must ground a question the same way — same page text, same
evidence, same rule about not inventing a date. Two copies would drift, and the
copy that drifted would be the one that made something up
(`coding-standards.md` §1.1).

### 3.2 Why the loop is in layer 4, which looks wrong until it doesn't

The loop needs two things: the `Document` the pages come from (layer 2) and the
egress (layer 3). Layer 4 is the only layer that may import both
(`coding-standards.md` §1).

It cannot move down into `Gate`, because `Gate` depends on **`Contracts`
alone** — not on `Tools`. That is the load-bearing choice: an egress that can
reach `Tools` can rasterise and read a file, and the single thing this boundary
promises is that it cannot. Giving `Gate` a `Document` would hand the one
network-capable target a handle on the user's file.

It cannot move down into `Agent` either: *"an agent that opens a socket has
leaked layer 3 into layer 2. That one is a bug against invariant I1, not a style
issue"* (`coding-standards.md` §1).

So layer 4 is not where the loop landed for convenience. It is the only place
the layer rule permits, and `Sources/UI/Explained.swift`-shaped free functions —
pure, injected transport, no `@MainActor` — are how layer 4 holds logic without
becoming a view.

### 3.3 The one tool

```
read_page(page: integer)  →  that page's text, capped at Limits.askPageChars
```

One tool, because one is what the feature needs. `coding-standards.md` §1.2 —
no abstraction with a single implementation, and a tool *registry* for one tool
is exactly that. When a second tool is genuinely needed, the shape to reach for
is a list, not a protocol.

A call for a page outside `1…pagesRead` returns *"that page is not available"*
as an ordinary tool result. It does not throw. One badly-aimed call must not
cost the reader their turn.

### 3.4 What goes out, and what never does

| Goes | Never goes |
|---|---|
| The open page's text, capped | The source file's bytes |
| Pages the model asked for, capped, one at a time | The filename or its path |
| Values already recognised on the open page, with their quotes | Any page image or crop — this feature sends **no image at all** |
| The question, and up to `Limits.askHistory` earlier turns | The key, anywhere but the `Authorization` header |

The recognised values travel because they are the only part of the payload
carrying provenance: each has already been checked against the transcript at the
construction point that enforces **I2**. Sending them saves the model
re-deriving what the machine already knows, and gives it a quote to cite.

---

### 3.4a The on-device tier, and why *this* feature is where it becomes possible

Apple's window is **4096 tokens for prompt and answer combined**, fixed
(`architecture.md` §3). That number is the reason whole-document explanation
needs chunking and map-reduce, and it is why F4 treats Foundation Models as
optional rather than foundational.

**A single-page question is the one workload it comfortably fits.** Measured in
`architecture.md` §3: one OCR'd EPA page is ~530 tokens. Instructions are ~250.
A question and its answer fit in what is left, with room to spare —
`Limits.localPromptTokens` spends 2,400 of the window on the prompt so the reply
is not truncated into looking like the model trailing off.

So the constraint that makes F4 hard does not bind here. This feature is where
*"on a machine with a local reasoning model, nothing leaves — full stop"*
(`project-overview.md` §3) stops being an intention and becomes code.

| | Cloud tier | On-device tier |
|---|---|---|
| Where | `Sources/Gate/` + the hop loop in layer 4 | `Sources/Agent/LocalModel.swift`, in-process |
| Sees | the open page, plus pages it fetches | **the open page only** |
| Fetching other pages | `read_page`, bounded | none — the window that makes one page possible makes several impossible |
| Consent | granted once per document | **none, because nothing leaves** |
| Inspector ledger | one line per page sent | **empty, by construction** |

The instructions differ by exactly one paragraph
(`Document.askInstructions(canFetchPages:)`): the on-device model is told it can
see only this page and should name the page that likely carries the answer,
rather than being offered a tool it cannot afford to call. Everything else —
the page, the evidence, the rule about never inventing a date — is one shared
builder in layer 2, because two copies of *how a question is grounded* would
drift, and the copy that drifted would be the one that made something up.

**Inference in-process is not egress.** `scripts/layers.sh` keeps
`import FoundationModels` inside `Sources/Agent/`, and that file opens no
socket. The distinction is the whole reason the tier is worth having.

**Degradation, and what gives way first.** A page can carry forty recognised
values whose quotes are verbatim OCR lines, and that block can be larger than
the page it describes — while the page itself is already capped at
`askPageChars`. So the evidence is dropped before the page is: the model can
re-derive a value from the text underneath, but it cannot re-derive the text.
`LocalModel.Failure.tooLong` remains as the backstop after that.

**Not testable end to end on this machine.** `SystemLanguageModel.default.availability`
returns `unavailable(appleIntelligenceNotEnabled)` here — the hardware is
eligible, the switch is off (`progress-tracker.md`). Every test injects
`LocalModel.Respond`, so the plumbing, the budget and the tier preference are
all covered; **the quality of on-device answers is unmeasured** and is recorded
as such in §10.

### 3.5 The tier is what decides whether asking exists at all

`readingTier` is picked at first run and stored. Until review caught it, **only
`OnboardingScreen` ever read it** — `ReaderModel` derived `cloud` straight from
the environment — so a reader who chose *On this Mac* was still handed a
cloud-backed ask panel.

That is worse than an undisclosed fallback. An undisclosed fallback is something
the reader was never told; this was something the reader **explicitly
declined**, and the app did it anyway.

`ReaderModel.honour(_:)` applies the tier, and `ReaderModel.askConfig` is the
pure rule behind it so it can be tested without a window:

| Tier | `cloud` | The panel says |
|---|---|---|
| `.openAI`, key present | the config | the host, above the field |
| `.openAI`, no key | `nil` | "No key is set… export `OPENAI_KEY`" |
| `.local`, model ready | **`nil`, always** — it answers here instead | "answered on this Mac — nothing leaves, and there is nothing to agree to" |
| `.local`, Apple Intelligence off | `nil`, and nothing local either | the reason, from `localModelBlocker()` — a switch in System Settings, a download in progress, or a Mac that cannot |

`.local` **never** resolves to a cloud endpoint. It answers on this machine or
it says why it cannot, and the three reasons are distinguished because they need
different things from the reader: a switch in System Settings, patience while
macOS finishes a download, or a Mac that will never run it. Telling someone with
an eligible Mac to buy a new one, or someone with an ineligible one to go
hunting in Settings, are both worse than saying nothing.

And when the on-device model *is* available it **wins** — `ReaderModel.send`
tries it before the endpoint, even with a key in the environment. A preference
the code consults second is a preference the code does not hold.

The onboarding copy was corrected in the same diff — two cards claimed *"this
build has no network code in it at all"* and *"this build sends nothing yet"*,
and both stopped being true the moment layer 3 landed.

---

## 4. The bound, and why the last hop withdraws the tool

`Limits.askHops = 4`. The loop exists for one job — *"the rates are not on this
page, they are on the rate table"* — and a model needing a fifth page to answer
a question about the page in front of the reader is no longer answering that
question.

The naive bound is "stop after N and give up", which spends four requests and
returns nothing. Instead, **the last pass is made with the tool withdrawn**, so
the model must answer with what it has. The bound then costs a hop of latency
and never costs the answer. If it still only asks for pages, the reader is told
that is what happened, rather than shown a blank.

This is **I10** ("the chunk loop is bounded") applied to a loop the invariant
was not written for. The shape generalises: bound by removing the option, not by
abandoning the turn.

### 4.1 `askHops` bounds rounds. `askPages` bounds what leaves.

The first version had only `askHops`, and review found the hole: **one reply may
legally carry a hundred `read_page` calls**, and the loop appended every
requested page before the next request. A single over-eager response therefore
sent an entire document from inside a loop that called itself bounded.

Bounding rounds is not bounding egress. `Limits.askPages = 6` is the bound that
counts the thing that actually leaves, and it is charged **per new page**, so a
model asking for page 3 four times spends one page of budget, not four. Calls
past the budget get an ordinary tool result saying so, which the model can act
on — the alternative, refusing any reply that carries more than one call, makes
a legitimate two-page question fail.

### 4.2 I13 is an assertion, not an effort

The trim loop drops the oldest turns and stops at one, which cannot help when
the *newest* turn is itself over budget — so an oversized payload was trimmed as
far as possible and then posted anyway. `Gate.Failure.promptTooLarge` is now
thrown before the request is built.

Defence in depth means it should never fire: `askPageChars` caps a page,
`askQuoteChars` caps each evidence quote (a verbatim OCR line, unbounded at
source), and `askQuestionChars` caps whatever was pasted into the field. Those
caps are why a real document cannot produce a refused request — and the guard
stays, because a limit that fails silently at the far end is exactly the kind
you assert at the near one.

### 4.3 The ledger records what left, not what was attempted

`sends` was written *before* the transport ran, so an offline machine still
produced `page 1 text → api.openai.com`. **Claiming text left when it did not is
the dangerous direction for this app to be wrong in**, so pages now move into
the ledger only once the wire has carried them, and the failure is classified
three ways rather than two:

| Outcome | Ledger |
|---|---|
| The server answered — 200, or 401, or 500 | recorded plainly; the bytes left |
| `promptTooLarge` — refused before the request was built | **no entry**; nothing left |
| Anything else — a dropped connection mid-write | recorded with `send failed, may not have arrived` |

Three cases, not two, because two would force a guess. Under-reporting egress is
the failure that matters here, so "unknown" is reported as unknown rather than
rounded down to "nothing".

---

## 5. An answer is not a `Finding`, and that is the whole honesty story

The tempting move is to let a good answer become a finding — it has a value, it
has a page, the model even quoted something.

It must not, and the reason is mechanical rather than stylistic. `Finding`'s
initialiser is `package`, and `Tools.finding(…)` is the **one** construction
point:

```swift
guard !quote.isEmpty, transcript.contains(quote) else { return nil }
```

That check is what makes **I2** a rule instead of a comment
(`architecture.md` §11, and the decision-log row that made `Finding`
`Encodable`-only). A `Finding` minted from model prose would either bypass the
check or force it to special-case a new origin — and at that point every ring
and every export in the app inherits a value nothing verified.

So chat prose stays prose. What it carries instead is **which pages it rests
on**, rendered under the answer, so a claim can be checked against the page it
came from. That is weaker than a verbatim quote, and it is honest about being
weaker — which is the trade this product makes everywhere else too.

---

## 6. Two sentences in the UI that stopped being true

Both were true *by construction* while no Gate layer existed, and both are the
kind of claim that rots silently.

| Where | Was | Now |
|---|---|---|
| `ReaderScreen` header | `Reads locally` | Reading still is — the rasterise/OCR/findings path touches no network. Asking is not. The chip names the host once a grant is given. |
| `inspectorBlock` | `Left this machine: nothing.` | A ledger: `page 12 text → api.openai.com · 2,131 chars`, one line per send. |

The ledger holds **page number, character count and host, and nothing else**.
`coding-standards.md` §5.2 forbids document text, crop bytes, filenames, paths
and keys in a log, and inspector mode is a view, not an exemption from it —
`issues.md` 7.1's stress table already said so before this feature existed.

A chip that is true of the reading path and quietly false of the asking path is
precisely the *"fallback you have to discover"* that `project-overview.md` §3.1
rules out. Changing both in the same diff as the egress is not politeness; it is
the diff being complete.

---

## 7. TDD flow

Written first, in `Tests/PigeonEyeTests/AskTests.swift`, transport injected
throughout — **no test in this feature touches the network**.

| # | Test | Holds |
|---|---|---|
| 1 | `the_question_carries_the_open_page_and_not_the_rest` | grounding — page 2's words go, pages 1 and 3 stay |
| 2 | `recognised_values_on_the_page_travel_with_the_question` | provenance travels |
| 3 | `a_read_page_call_fetches_that_page_and_records_it` | the hop works and is recorded |
| 4 | `a_model_that_only_ever_asks_for_pages_is_cut_off_and_still_answers` | **I10** |
| 5 | `a_call_for_a_page_that_was_never_read_does_not_lose_the_answer` | one bad call ≠ a dead turn |
| 6 | `nothing_is_sent_before_the_reader_grants_it` | **I1** |
| 7 | `opening_another_document_clears_the_chat_and_the_grant` | **I9** |
| 8 | `a_refused_key_leaves_the_document_on_screen` | **I6** |
| 9 | `an_empty_reply_is_not_rendered_as_an_answer` | `project-overview.md` §9 |
| 10 | `the_send_record_names_the_page_and_never_its_words` | §5.2 |
| 11 | `a_question_mark_typed_into_a_field_is_a_question_mark` | the monitor fix |
| 12 | `choosing_on_this_mac_turns_asking_off` | §3.5, the pure rule |
| 13 | `the_local_tier_sends_nothing_even_with_a_key_in_the_environment` | §3.5, end to end |
| 14 | `an_oversized_question_is_refused_before_anything_is_sent` | §4.2, **I13** |
| 15 | `a_pasted_wall_of_text_is_capped_rather_than_refused` | §4.2, the caps in front of it |
| 16 | `one_over_eager_reply_cannot_send_the_whole_document` | §4.1, `askPages` |
| 17 | `an_offline_machine_does_not_report_text_as_having_left` | §4.3 |
| 18 | `a_rejected_request_still_reports_that_the_text_left` | §4.3, the other direction |
| 19 | `the_local_tier_answers_without_touching_the_transport` | §3.4a — the pitch, as a test |
| 20 | `the_local_tier_asks_for_no_grant` | nothing leaves, so nothing to consent to |
| 21 | `the_local_tier_is_preferred_over_a_configured_endpoint` | local wins when it is there |
| 22 | `a_chosen_but_unavailable_local_tier_says_why_and_sends_nothing` | no silent fallback to the declined tier |
| 23 | `evidence_gives_way_before_the_page_does` | **I13** on the 4096-token window |
| 24 | `an_ordinary_page_fits_the_on_device_window` | the guard is not merely an off switch |
| 25 | `a_local_failure_says_nothing_left_the_machine` | the assumption a reader would otherwise make |

**The F1 lesson applied.** A green test proves nothing until it has been seen
red. Both invariant guards were mutated and the suite re-run:

| Mutation | Test that went red |
|---|---|
| Drop the `askGranted` guard in `ReaderModel.send` | #6 — the transport recorded a request |
| Widen `pageText` from one page to `doc.transcript` | #1 — `Marker1` and `Marker3` appeared on the wire |
| `askConfig` returns `offered` whatever the tier | #12 and #13 — the local tier sent |
| Remove the `askPages` guard | #16 — one reply sent all 10 pages |
| `sent(_:)` always returns `.yes` | #17 — an offline machine reported text as having left |
| Cloud path taken even when the local model is ready | #19 and #21 — the transport was reached |
| Never drop evidence when over the on-device window | #23 — `tooLong` thrown on a page that should fit |

All reverted. This is the check `progress-tracker.md`'s F1 review says a stress
table without tests is missing — and the last three mutations exist because the
guards they test were **added after review found them absent**, which is the
same lesson arriving a second time.

---

## 8. Acceptance criteria

- [x] The open page's text goes out; the pages either side of it do not
- [x] Values recognised on that page travel with the question, quotes included
- [x] `read_page` fetches a page the model was not shown, and the answer names it
- [x] The hop loop is bounded and still returns a sentence (**I10**)
- [x] Nothing reaches the transport before the reader grants it (**I1**)
- [x] Opening another document drops the conversation *and* the grant (**I9**)
- [x] A refused key, a 429 or an unparseable reply leaves the document untouched (**I6**)
- [x] At most `Limits.askPages` pages leave to answer one question, however many the model asks for
- [x] The token budget is asserted against the bytes that go out, before they go (**I13**) — and refuses rather than trims-and-posts
- [x] The tier picked at first run decides how a question is answered; `.local` answers on this Mac and sends nothing
- [x] The on-device tier is preferred over a configured endpoint when it is available
- [x] `.local` with the model unavailable says which of the three reasons it is, and does not fall back to the cloud
- [x] The on-device prompt is asserted against the 4096-token window, dropping evidence before the page (**I13**)
- [x] The ledger records a page only once the wire has carried it, and says so when that is uncertain
- [x] No `Finding` is minted from an answer, so **I2** is untouched
- [x] The inspector's record names page, size and host — never words, filename or key
- [x] `rg 'URLSession|http' Sources | grep -v '^Sources/Gate/'` is empty

---

## 9. Stress test

Every row is a test above, or a hand-check named as one.

| Case | Must happen |
|---|---|
| **A model that only ever calls `read_page`** | Cut off at the bound; the reader still gets a sentence saying why. An unbounded loop is an unbounded bill. |
| **A call for page 99 of a 3-page document** | Answered, not thrown |
| **Endpoint returns 200 with an empty body** | Not rendered as an answer — §9's "empty result dressed as success" |
| **No key in the environment** | The panel says so and shows no field. A box that cannot send is worse than no box. |
| **Typing `?` into the ask field** | The character appears. The bare-`?` monitor sees *every* keystroke in the app, so before `opensList(typing:)` it swallowed the character and opened the shortcuts sheet. A shortcut that steals characters out of a field is worse than no shortcut. |
| **A 45-page document, one question** | One page of text leaves per hop — not 32,394 tokens of transcript. Check the payload, not the intent. |
| **Ask, then open another document mid-flight** | The answer lands on nothing. Covered by the same `requestID` generation check as every other `await` in `ReaderModel`. |
| **Scrape the inspector after a full run** | No document text, no filename, no path, no key |
| **One reply carrying nine `read_page` calls** | At most `Limits.askPages` pages leave. Bounding rounds is not bounding egress. |
| **The reader picked "On this Mac" and a key is in the environment** | Nothing is sent, and the panel says why — the reader declined this, which is stronger than never having been told |
| **Pull the network mid-question** | The ledger says `send failed, may not have arrived`, not that the page left and not that it didn't |

---

## 10. Known ceilings

Each is deliberate, and each names what would lift it.

| Ceiling | Why it is acceptable now | The upgrade |
|---|---|---|
| `Gate.estimatedTokens` is `count / 4`, not a tokeniser | Over-counts ordinary English, so it errs toward sending **less** than allowed — the safe direction for a limit that fails silently | A real tokeniser, if a page is ever cut that did not need to be |
| Over-budget drops the **oldest turns** | The turn holding the current page is last, so what goes first is history — the part the reader can most afford to lose | Summarise dropped turns instead of discarding them |
| Answers cite pages, not quotes | A quote would have to survive **I2**'s substring check to mean anything, and prose that failed it would have to be discarded — losing the answer to protect a guarantee it never claimed | Ask the model for a verbatim span, run it through `Tools.finding`, and render the ones that survive as real findings |
| One question at a time | `answering` gates the field. Two in flight would interleave on one `turns` array | A per-question generation token, if it is ever wanted |
| The conversation dies with the document | **I9**. There is no persistence path in this app and this feature does not add one | Nothing. This is the product, not a limitation |

---

## 11. Out of scope for F9

| Not built | Why |
|---|---|
| Sending a crop or a page image | That is F5, and it carries its own consent shape. This feature sends **text only** |
| Promoting an answer into `findings` | §5 |
| Asking across several documents | One document is open at a time; there is nothing to ask across |
| Persisting the conversation | **I9**, and "no accounts, no persistence" is a stated non-goal (`project-overview.md` §8) |
| Streaming the answer token by token | Costs an SSE parser in the one file whose whole defence is being short enough to read. A spinner and a paragraph is the same information |
| Letting the model act — export, navigate, fill a field | **I8**. It explains; it does not do |
