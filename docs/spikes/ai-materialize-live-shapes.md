# Spike — live wire shapes for AI (G15) and Create-from / materialize (G16)

**Audience:** engineering (the Thread 2 implementers and anyone re-verifying these routes).
**Date:** 2026-09-05 · **Account:** the `.env` contract-test account (`messenger@interlinedlist.com`, subscriber) via `POST /api/auth/sync-token` → Bearer.

The live OpenAPI spec models these routes as `{"feature": string}` and `{"source": string}` and nothing more, so the real contracts were recovered two ways: **non-mutating probes** against the live routes, and **reading the web client's own call sites** in the public Next.js chunks under `/_next/static/chunks/`. Both are reproducible; neither spends AI quota or creates data.

> **No AI calls were spent and nothing was created.** Every probe below either fails validation before the model runs, or resolves a source id that does not exist. The feature enum in particular was mapped purely from the *difference* between two rejection messages.

## AI — `GET /api/ai/status`

Live response for a configured subscriber:

```json
{ "subscriber": true, "providers": ["anthropic"],
  "defaultModels": { "anthropic": "claude-sonnet-5", "openai": "gpt-4.1-mini", "gemini": "gemini-2.0-flash" },
  "quota": { "usedToday": 0, "dailyLimit": 50, "remaining": 50 } }
```

AI is subscriber-gated **and** requires the account to have supplied its own provider key on the web Integrations page, so `providers` can be empty for a paying user. Call this before showing the assistant so a refusal can be explained rather than thrown.

## AI — the `feature` enum (complete)

Mapped by probing `POST /api/ai/suggest` with `{"feature": "…"}` and **no `input`**. A known feature answers `422 {"error":"Input is required."}`; an unknown one answers `422 {"error":"Unknown or missing feature."}`. Neither runs a model.

| `feature` | Product surface (per `/help/ai`) |
| --- | --- |
| `writing_assist` | Composer assistant |
| `message_series` | A brief → a sequence of connected short posts |
| `article_series` | A brief → a sequence of connected documents |
| `powered_template` | AI list template — drafted schema + starter rows |
| `powered_document` | AI document |

Everything else tried (`list_template`, `powered_list`, `ai_list`, `list_from_prompt`, `list_schema`, `list_assist`, `list_builder`, `list_starter`, `schema_suggest`) is rejected — the enum is exactly these five.

## AI — `POST /api/ai/suggest` → `{ artifact }`

Request: `{ feature, input, context? }`. `suggest` **previews only**; nothing persists until the artifact is posted back to `generate`.

| feature | `context` | artifact members |
| --- | --- | --- |
| `writing_assist` | `{ action }` | `kind:"text"` + `content` · `kind:"thread"` + `parts[]` · `kind:"tags"` + `tags[]` |
| `message_series` | `{ channels: ["Bluesky", …] }` | `items[].content` |
| `article_series` | — | `documents[].title` |
| `powered_document` | `{ mode }` (+ `listId` / `documentId` / `url`) | `title`, `outline`, `markdown` |
| `powered_template` | **unverified** | **unverified** |

`writing_assist` actions, with the web client's labels: `rewrite` "Rewrite" · `tighten` "Tighten to fit" · `expand` "Expand" · `grammar` "Fix grammar" · `thread` "Split into thread" · `tags` "Suggest tags".

`powered_document` modes: `article` (topic) · `from_list` (+`listId`) · `from_article` (+`documentId`) · `research_url` (+`url`).

Client-side gates the web app applies before calling: **2 words** minimum for the assistant, **10 words** for a series. Series parts are sized to the smallest selected cross-post limit — Bluesky 300, Mastodon 500, LinkedIn 3000, X/Twitter 280.

## AI — `POST /api/ai/generate` → `{ created }`

Request: `{ feature, artifact }`, plus `{ crossPost, scheduleImmediately }` for `message_series` only.

- `message_series` → `created.scheduledMessageIds[]` + `created.firstScheduledAt` when scheduled, else `created.listId`.
- `powered_document` → `created.documentId`.

The artifact is echoed back **verbatim**, so `AIArtifactDTO` keeps the raw JSON alongside its modelled members; a server member this client never modelled still survives the round-trip.

## Materialize — `POST /api/materialize`

Request: `{ target, source, listConfig?, docConfig? }`.

- `target` ∈ `list` · `doc` · `both`. Anything else → `400 "Invalid target"`.
- `source` (from the web client's own `sourceRef`): `{kind:"messages",messageIds:[…]}` · `{kind:"lists",listIds:[…]}` · `{kind:"rows",listId,rowIds:[…]}` · `{kind:"document",documentId}` · `{kind:"docElements",documentId,markdown}`.
- `listConfig`: `{ title, description?, isPublic, fields, includeData }`. A list target with no title → `400 "A list title is required"`.
- `docConfig`: `{ title, relativePath?, isPublic, listStyle, rowDataStyle }`, where `listStyle` ∈ `bulleted`/`numbered` and `rowDataStyle` ∈ `table`/`inline`/`paragraph`.

Source refs were confirmed by sending well-formed refs with unknown ids: `404 "One or more messages are unavailable"` and `404 "Document is unavailable"` prove the shape parsed **and** that nothing was created.

### ⚠️ Unresolved — `listConfig.fields` is rejected no matter what

Every descriptor tried returns the identical `400`:

```
{"error":"Invalid list schema: Field at index 0 must have a 'key' property (string)","code":"bad_request"}
```

Tried, all with a **real** message id so validation ran past source resolution: `[{"key":"content"}]`, `[{"key":"content","type":"text"}]`, `[{"key":"content","label":"Content","type":"text"}]`, `[{"key":"content","name":"Content","type":"text","nullable":true}]`, `[{"key":"Content","type":"text"}]`, `[{"key":"content","type":"string"}]`, `["content"]`, `[{"nokey":1}]`.

A payload that plainly carries a string `key` is rejected for not carrying a string `key`, so **the message does not describe the check that is failing** — the validator is reading a field array from somewhere other than `listConfig.fields`, or the descriptor needs a member no guess has hit. Consequences:

- **`target: "doc"` is usable. `target: "list"` and `"both"` are not**, until this is resolved.
- Two ways to resolve it, in order of cost: **(a)** capture the web app's own successful request from a logged-in browser session (the payload is only assembled on submit, so it needs a real Create click, or a breakpoint on `fetch`); **(b)** ask the backend for the `listConfig.fields` contract — this is a new §2 backend ask if (a) fails.

## Reproducing

```bash
set -a; source .env; set +a
TOK=$(curl -s -X POST https://interlinedlist.com/api/auth/sync-token -H 'Content-Type: application/json' \
  -d "{\"email\":\"$INTERLINEDLIST_EMAIL\",\"password\":\"$INTERLINEDLIST_PASSWORD\"}" | jq -r .token)
curl -s https://interlinedlist.com/api/ai/status -H "Authorization: Bearer $TOK"
# feature probe — rejects before any model call, costs nothing:
curl -s -X POST https://interlinedlist.com/api/ai/suggest -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' -d '{"feature":"powered_template"}'
```

Web call sites: fetch `https://interlinedlist.com/` and `/documents`, harvest `/_next/static/chunks/*.js`, and grep for `/api/ai/` and `/api/materialize`. Chunk hashes change on each deploy — re-harvest rather than reusing the paths here.
