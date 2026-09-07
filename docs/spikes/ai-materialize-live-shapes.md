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

## AI — `POST /api/ai/suggest` → the full envelope

Request: `{ feature, input, context? }`. `suggest` **previews only**; nothing persists until the artifact is posted back to `generate`. The response is a full envelope, not the bare `{artifact}` the web client destructures:

```json
{ "ok": true, "feature": "writing_assist",
  "artifact": { "kind": "message", "content": "…" },
  "usage": { "inputTokens": 128, "outputTokens": 25, "model": "claude-sonnet-5" },
  "quota": { "usedToday": 1, "dailyLimit": 50 } }
```

`usage` and `quota` are worth surfacing — the user is spending their own provider key.

### Artifacts, captured one live call per feature (2026-09-05)

| feature | `context` | artifact |
| --- | --- | --- |
| `writing_assist` rewrite/tighten/expand/grammar | `{ action }` | `kind:"message"`, `content` |
| `writing_assist` tags | `{ action:"tags" }` | `kind:"tags"`, `tags[]` |
| `writing_assist` thread | `{ action:"thread" }` | `kind:"thread"`, `parts[]` — **inferred from the web client, not exercised** |
| `message_series` | `{ channels:["Bluesky"] }` | `kind:"message_series"`, `listTitle`, `items[{order, content, crossPostTargets[]}]` |
| `article_series` | — | **unverified** — the one probe returned `502 {"error":"The AI provider rejected the request.","code":"provider_error"}` |
| `powered_template` | — | `kind:"list"`, `title`, `description`, `dsl{name, description, fields[{key,type,label,required,displayOrder}]}`, `rows[{…}]` |
| `powered_document` | `{ mode }` (+ `listId`/`documentId`/`url`) | `kind:"document"`, `title`, `markdown`, `outline[]`, `isPublic` |

> **`kind` is not what the web client's code implied.** A rewrite answers `kind:"message"`, not `"text"` — the web app only tests for `"tags"` and `"thread"` and treats everything else as prose, so the real value never appears in its source. Anything inferred from that `else` branch is a guess; this table is what the server actually sent.

`writing_assist` actions, with the web client's labels: `rewrite` "Rewrite" · `tighten` "Tighten to fit" · `expand` "Expand" · `grammar` "Fix grammar" · `thread` "Split into thread" · `tags` "Suggest tags".

`powered_document` modes: `article` (topic) · `from_list` (+`listId`) · `from_article` (+`documentId`) · `research_url` (+`url`).

Client-side gates the web app applies before calling: **2 words** minimum for the assistant, **10 words** for a series. Series parts are sized to the smallest selected cross-post limit — Bluesky 300, Mastodon 500, LinkedIn 3000, X/Twitter 280.

**Cost of this mapping:** 6 `suggest` calls out of a 50/day quota. No `generate` calls were made, so the `created` envelope is still only known from the web client's reads.

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

### `listConfig.fields` — resolved by capturing the web app's own request

Every guessed descriptor (`{key}`, `{key,type}`, `{key,label,type}`, `{key,name,type,nullable}`, bare strings) was rejected with:

```
{"error":"Invalid list schema: Field at index 0 must have a 'key' property (string)","code":"bad_request"}
```

**That message is misleading** — it describes the schema the server *derives*, not the request body, so a payload carrying a string `key` is rejected for not carrying a string `key`. Chasing it is a dead end.

The answer came from intercepting the web app's own request: `window.fetch` was patched in a logged-in tab to log the `/api/materialize` body and return a synthetic error **instead of** performing the call, so the real payload was captured with nothing created. The descriptor is:

```json
{ "propertyKey": "content", "propertyName": "Content",
  "propertyType": "textarea", "sourceKey": "content" }
```

— not `key`/`label`/`type`. `sourceKey` names the source attribute the column is filled from; the web app sets it equal to `propertyKey` for every default column.

`propertyType` values, from the column editor's `<select>`: `text` · `textarea` · `number` · `date` · `datetime` · `boolean` · `select` · `multiselect` · `email` · `url` · `tel` · `priority`.

The default columns for a **message** source are Content (`textarea`), Author (`text`), Posted (`text`), Links (`textarea`), Tags (`text`).

**Verified end to end 2026-09-05:** one real create against the test account with this shape returned `201` and the list was deleted immediately after.

```json
{"list":{"id":"8fad7ffb-…","title":"Recon verify (auto-deleted)"}}
```

Note the created object is **nested** under `list` — not a flat `listId`. `MaterializeResponse` decodes both and surfaces a flat `listId`/`documentId` either way.

## Live end-to-end pass — 2026-09-06

Every route exercised against the `.env` test account, including the persisting half. All six artifacts created were deleted afterwards and the account's inventory was confirmed back at its baseline (1 list, 5 documents, no leftovers).

| call | result |
| --- | --- |
| `powered_document` suggest → generate | `200` → `201 {"ok":true,"feature":"powered_document","created":{"documentId":"…"},"quota":{…}}` |
| `powered_template` suggest → generate | `200` → `201 … "created":{"listId":"…"}` |
| `message_series` suggest → generate (unscheduled) | `200` (5 items) → `201 … "created":{"listId":"…"}` — an unscheduled series collects into a list, as modelled |
| `materialize` target `doc` | `201 {"document":{"id":"…","title":"…"}}` |
| `materialize` target `both` | `201 {"list":{…},"document":{…}}` |
| `article_series` suggest | **`502 provider_error` — three attempts, three failures** |

The generate envelope carries `ok` / `feature` / `quota` alongside `created`; the created ids match what `AIGenerateResponse` and `MaterializeResponse` model, and the nested `list` / `document` objects match `MaterializeOutcome`.

### ⚠️ `article_series` is broken upstream, not in this client

Three separate attempts on two days, with different briefs (all comfortably over the ten-word minimum), returned the same body:

```json
{"error":"The AI provider rejected the request.","code":"provider_error"}
```

Every other feature succeeds on the same account, key, and model, so this is not entitlement, quota, or input length. The client models the feature and maps the failure to `AIError.providerRejected`, which presents as "the AI provider couldn't complete that request" rather than blaming the user — but the feature cannot work until the server side is fixed. Tracked as a backend ask in [`work-consolidation.md` §2](../../work-consolidation.md#2c-backend-confirmation--polish-asks).

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
