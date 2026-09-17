# Spike — the list and list-schema wire shapes

**Date:** 2026-09-15
**Account:** the `.env` contract-test account (`messenger@interlinedlist.com`)
**Method:** read-only `GET` probes, plus one create/update/delete cycle on a throwaway list
**Issues:** [#75](https://github.com/CompositeCode/interlinedlist-macos-native/issues/75), [#85](https://github.com/CompositeCode/interlinedlist-macos-native/issues/85); unblocks `P2-G` and item 1 of [#50](https://github.com/CompositeCode/interlinedlist-macos-native/issues/50)

## Why this exists

Three silent decode defects have shipped in this client — G21 link metadata, G25
org members, and the two fixed here — and every one of them had a **green test
written against a fabricated fixture**. A test that invents the payload it then
asserts against proves only that the decoder matches the invention.

So this file is the transcript. The tests in
`Packages/InterlinedKit/Tests/InterlinedKitTests/ListSchemaWireShapeTests.swift`
use these bodies verbatim.

## Headline finding

**The client modelled a list's schema as a DSL string. The API models it as an
object, and always has.**

```
POST /api/lists  {"title":"probe-string-schema","schema":"Title:text, Year:number"}
→ 400 {"error":"Invalid schema: DSL must be an object","code":"bad_request"}
```

That is what `CreateListRequest.schema: String?` was sending. Creating a list
with columns from macOS was a hard failure, not a degradation.

## Envelope map

| Route | Live shape | Client decoded | Consequence |
|---|---|---|---|
| `GET /api/lists` | `{lists[], pagination}` | ✅ correct | — |
| `GET /api/lists/{id}` | `{data:{…, properties[]}}` | bare `ListDTO` | `detail(listId:)` never decoded (#75) |
| `POST /api/lists` | `201 {message, data, refreshStatus?}` | bare `ListDTO` | create never decoded |
| `PUT /api/lists/{id}` | `{message, data}` | bare `ListDTO` | update never decoded |
| `GET /api/lists/{id}/schema` | `{data:{name, description?, fields[]}}` | `{schema:String}` | **schema editor + row table dead** |
| `PUT /api/lists/{id}/schema` | `{message, data:{…, properties[]}}` | `{schema:String}` | schema save was a 400 |
| `GET /api/users/{u}/lists/{id}` | `{list:{…}, ancestors[]}` | bare `ListDTO` | public list page never decoded |
| `GET /api/users/{u}/lists` | `{lists[], pagination}` | ✅ correct | — |
| `GET /api/lists/{id}/data` | `{rows[], pagination}` | ✅ correct | — |

Four distinct envelope conventions on one resource family: bare-keyed
collections, `{data}`, `{message, data}`, and `{list, ancestors}`. `OPTIONS`
proves the verb and says nothing about any of this.

⚠️ The `PUT …/schema` response **contradicts the OpenAPI 200 example**, which
shows a bare `{properties:[…]}`. The capture wins.

## The schema DSL object

`GET /api/lists/{id}/schema`, after setting help text, placeholders and
validation:

```json
{"data":{
  "name":"probe-object-schema",
  "description":"recon probe",
  "fields":[
    {"key":"title","type":"text","label":"Title","displayOrder":0,"required":true,
     "helpText":"What is it called?","placeholder":"e.g. Dune","visible":true,
     "validation":{"pattern":"^[A-Za-z].*$","maxLength":80,"minLength":2}},
    {"key":"year","type":"number","label":"Year","displayOrder":1,"required":false,
     "helpText":"Publication year","visible":true,
     "validation":{"max":2100,"min":1000}},
    {"key":"email","type":"email","label":"Contact","displayOrder":2,"required":false,"visible":true},
    {"key":"url","type":"url","label":"Link","displayOrder":3,"required":false,"visible":true},
    {"key":"due","type":"date","label":"Due","displayOrder":4,"required":false,"visible":true},
    {"key":"status","type":"select","label":"Status","displayOrder":5,"required":false,
     "visible":true,"defaultValue":"todo",
     "validation":{"options":["todo","doing","done"]},
     "options":["todo","doing","done"]}]}}
```

Three things to notice.

**1. `key` and `label` are different things, and row data is keyed by `key`.**

```json
"rowData":{"due":"2026-01-02","url":"https://example.com","read":true,
           "year":1965,"email":"a@b.com","title":"Dune","status":"done"}
```

`SchemaField` had one `name` serving as both. That was harmless only while the
client could not create a schema at all; the moment it could, a column labelled
"Publication Year" over a key of `year` would have rendered every cell empty.

**2. A `select` column carries its options twice** — under `options` and under
`validation.options`. Both are modelled and either alone resolves; reading only
one would work today and lose the options the day the server stops sending it.

**3. The validation vocabulary is first-class**, not DSL syntax:

```
validationRules: { min, max, minLength, maxLength, pattern, options }
helpText · placeholder · isRequired · isVisible · visibilityCondition
defaultValue · displayOrder
```

`work-consolidation.md` `P2-G` recorded this encoding as API-unconfirmed, which
is what blocked item 1 of #50. It is confirmed, and there is no encoding to
reverse-engineer — the fields simply exist.

`visibilityCondition` is conditional column visibility. It was `null` on every
captured payload, so it is decoded type-erased rather than guessed at; modelling
an unseen shape is precisely how G21 and G25 happened.

## The property projection

The same columns come back under a **second spelling** wherever a list object is
returned (`data.properties`):

```json
{"id":"3096cb0f-…","listId":"851954cb-…",
 "propertyKey":"title","propertyName":"Title","propertyType":"text",
 "displayOrder":0,"isRequired":true,"defaultValue":null,
 "validationRules":{"pattern":"^[A-Za-z].*$","maxLength":80,"minLength":2},
 "helpText":"What is it called?","placeholder":"e.g. Dune",
 "isVisible":true,"visibilityCondition":null,
 "createdAt":"…","updatedAt":"…"}
```

`ListPropertyDTO.asSchemaField` reconciles the two so no caller above the kit has
to know there are two.

## The destructive-change guard

`PUT /api/lists/{id}/schema` refuses to drop a column that still holds row data:
`400` plus a `propertiesWithData` array naming them, and `?force=true` confirms.
The client knew nothing about this, so it presented as an unexplained failure.

⚠️ **The column list is not reachable from `APIError` today.** `APIError.badRequest`
carries only the decoded `{error}` string; the rest of the body is discarded at
`APIClient.swift:234`. `ListSchemaConflictDTO` models the full shape, and
surfacing the names becomes a one-line change once the kit keeps the body. Filed
separately.

## `ListDTO.schema` was always nil

`ListDTO` declared `schema: String?`, documented as *"present on detail and
create responses"*. **No captured payload carries a `schema` key on a list
object.** So `OwnedList.schemaDescription` — rendered in the list detail header
and in the Markdown export — has always been empty. It is now derived from the
real columns.

## What was written during this spike

One throwaway list (`probe-object-schema`) was created, given a schema twice, had
one row added, was made public for the public-route probe, and was deleted
afterwards. Nothing else on the account was touched.
