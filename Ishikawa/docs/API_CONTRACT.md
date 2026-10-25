# Versioned Chat API Contract

## Boundary

The native retrieval API exposes two nonstreaming application routes:

- `POST /v1/chat` for grounded conversation; and
- `POST /v1/document` for progressive, read-only reconstruction of one exact
  active document version.

The browser calls the Next.js API. Next.js calls this loopback retrieval API.
The browser does not call PostgreSQL, Nomic, Gemma, or this native service
directly and holds none of their credentials.

## Request

The exact `ishikawa.chat-request.v1` request contains:

- stable opaque conversation and current-turn identities;
- the current user message;
- bounded, alternating prior user/assistant turns with their identities;
- optional structured references to a previously returned `Source N` and an
  optional citation within that source; and
- allowlisted document-class and document-key filters.

History must end with an assistant turn, making the current `message` the next
user turn. Turn identities are unique within the request. Clients cannot
select internal method-profile, corpus-publication, embedding-space, prompt,
model, endpoint, or authorization identities.

The profile allows at most 12 prior turns, 65,536 history characters, 16,384
question characters, 20 source references, 20 values in either filter, and
262,144 encoded request bytes. Duplicate JSON fields, unknown fields,
non-finite numbers, invalid UTF-8, malformed identities, and limit violations
fail closed before orchestration.

## Response

The v1.3 candidate returns the exact `ishikawa.chat-response.v5` response. It
repeats the conversation and
turn identities and adds one opaque request-correlation identity. Its status
is exactly one of:

- `answered`;
- `clarification-required`;
- `insufficient-evidence`;
- `out-of-scope`;
- `security-rejected`;
- `context-limit`;
- `temporarily-unavailable`; or
- `internal-error`.

An answered response contains one ordered sequence of coherent `segments` and
client-safe source groups. Every segment contains answer prose plus one or
more allowlisted citation identities. There is no second model-authored or
API `answer` field and no duplicate numbered claim list.
Each source group represents one document version and has its conversation-stable
`Source N` label, stable catalog document key, nullable conservative
self-declared identifier, display name, assigned class, and one or more excerpts. Each
excerpt contains its opaque citation identity, approved exact text, page
range, structural path, and optional table, row, form, field, procedure, or
step anchor. The group also carries the authoritative positive total page
count for that exact document version. Every segment citation must resolve to
an included excerpt, and no excerpt page may exceed that total.
Only complete structural roots used by the validated response are initially
returned for display. `has_additional_sections` reports that the exact active
document has other sections available through the document-view route.

An answered response also carries the measured total token limit, tokens used,
and safe tokens remaining for that completed request. This value comes from
the same Gemma token-counting and reconstruction budget used by the Retrieval
API; it is not estimated in the browser. Non-answer responses carry `null`.

A public response also contains one required `diagnostics` object. After the
Retrieval API completes orchestration, this strict content-free object carries
the allowlisted stage timings, retrieval timing breakdown, lane states, result
counts, Nomic and Gemma token counts, selected prompt target, context counts,
retry observation, deterministic relevance and sufficiency reason codes, and
the final bounded selection-group order. The group order contains only opaque
version/group identities and at most six values. The retrieval breakdown is limited to Nomic, lexical
SQL, vector SQL, fusion/ranking, reconstruction, and tokenization. A stage
or count not reached is `null`; no content, score, prompt, credential,
endpoint, path, vector, exception, or raw model response can be represented.

A clarification response contains only the clarification question. Every
other non-answer status contains only its exact allowlisted error code and safe
message. Raw exceptions cannot be passed through this builder.

## Reconstructed-document response

The exact `ishikawa.document-view-request.v1` request contains only an opaque
`source_id`, a section offset, and a bounded section limit. `source_id` is the
document-version identity already returned with a citation. The
`ishikawa.document-view-response.v2` response returns document metadata,
the exact document version's authoritative total page count, and
ordered structural sections with selectable text, page ranges, and unit
kinds. The reader uses a `REPEATABLE READ, READ ONLY` transaction and fails
closed if that exact version is no longer active. It never calls Gemma.

The browser may keep the viewer's open/collapsed state in memory. It does not
write reconstructed document bodies to browser `sessionStorage`; after a page
refresh the body must be requested again from PostgreSQL. Viewed text is never
added to Gemma's conversation context.

## Exclusions

Filesystem paths, raw scores and ranks, prompts, credentials, internal
topology, stack traces, and private method identities are not response fields.
Streaming and original-PDF open/download are disabled. The reconstructed-text
viewer is not a PDF route and exposes no source filesystem path.

The API profile is versioned independently. A material change to required
fields, identities, status meaning, citation meaning, limits, or authorization
behavior requires a new API version and qualification.
