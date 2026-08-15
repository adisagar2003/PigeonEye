# PigeonEye

Government document reader. Context lives in [context/](context/) — [project-overview.md](context/project-overview.md), [architecture.md](context/architecture.md), [progress-tracker.md](context/progress-tracker.md).

## Run it

```sh
swift build && swift run PigeonEye
swift test                    # ~45s
sh scripts/layers.sh          # layer + root-cleanliness checks — before any commit
```

Reading a document is entirely local and needs nothing configured. **Asking a
question about a page** is the one thing that leaves the machine, and it needs a
key:

| Variable | Default | |
|---|---|---|
| `OPENAI_KEY` or `OPENAI_API_KEY` | — | without one the ask panel says so and shows no field |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | any OpenAI-compatible endpoint, including a local one |
| `OPENAI_MODEL` | `gpt-4o-mini` | |

Nothing reads `.env` — export it, or pass it on the command line:

```sh
OPENAI_KEY=sk-… swift run PigeonEye
```

`⌘K` puts the caret in the ask box; `?` lists every shortcut.
