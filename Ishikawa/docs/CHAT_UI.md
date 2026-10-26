# Ishikawa Chat UI

## Purpose

The Ishikawa Chat UI is the browser-facing part of the application. It runs
from host-resident source bind-mounted read-only into the exact generic Linux
AMD64 Node 24 and Next.js 16 runtime image. The source is not baked into that
image. Every permanent start creates bounded ephemeral `.next` state, runs
`next build`, and then runs `next start` in the same container.

The browser communicates only with the Next.js server. The Next.js server
proxies versioned chat requests to the loopback Ishikawa Retrieval API. The
browser never receives the native retrieval URL, model credentials, database
credentials, or direct access to PostgreSQL, Nomic, or Gemma.

```text
Browser
  ├── GET  /
  ├── GET  /api/live
  ├── GET  /api/ready
  ├── GET  /api/dependencies
  ├── POST /api/v1/chat
  └── POST /api/v1/document
             │
             ▼
        Next.js server
             │ POST /v1/chat or /v1/document
             ▼
        Retrieval API on loopback
```

## Configuration boundary

The container launcher validates `product.yaml` and `deployment.yaml`, then
supplies these server-only runtime values:

- `ISHIKAWA_PRODUCT_DISPLAY_NAME`, derived from `product.display_name`; and
- `ISHIKAWA_PRODUCT_UI_CONFIG_BASE64`, the canonical validated tagline,
  quick-question, footer, and empty-chat presentation payload; and
- `ISHIKAWA_RETRIEVAL_BASE_URL`, derived from
  `deployment.web.retrieval_base_url`.

The retrieval URL must use plain HTTP on a loopback host with an explicit
port. It is consumed only by server routes. Changing the product display name
does not rebuild the image or application source. Every product key and the
restricted formatting subset are documented in
[`PRODUCT_PRESENTATION_CONFIGURATION.md`](PRODUCT_PRESENTATION_CONFIGURATION.md).

## Workspace and conversation behavior

The visual shell follows the accepted shared product patterns while retaining
Ishikawa's separate purpose and implementation. One semantic CSS-token system
supplies violet light and dark themes. The full-width header, three-region
desktop grid, compact bordered cards, scroll ownership, and pinned composer
provide a consistent structure and visual rhythm. Ishikawa does not expose a
code workspace, uploads, model selector, artifact controls, or review workflow.

The desktop workspace has three panes. The left pane provides the primary new
chat action; creates, selects, scrolls, and renames chats; and exposes local
quick questions. The center pane owns the active transcript and pinned
composer. The right pane shows citations for the currently selected
question/response turn as collapsed expandable cards and Gemma and Nomic
availability. The newest completed response is selected by
default; selecting either card in an older turn replaces the rail contents
without altering the transcript. The right rail collapses first at
reduced widths, followed by the left rail.

The theme initially follows the operating-system preference. The operator can
change it with the header control. Only the `ishikawa.theme` preference is
retained in `localStorage`; changing theme does not change application data or
behavior.

Chats persist only in browser `sessionStorage`. They survive page navigation
and refresh within that browser session, but are not stored in PostgreSQL,
shared across browsers, or associated with a user account. Reconstructed full
document bodies are deliberately excluded from that stored chat state. A
viewer can be reopened during the page lifetime, but refresh reloads its body
from PostgreSQL.

The page keeps the complete visible transcript for the current browser
session. Each request sends at most the newest 12 alternating prior turns and
65,536 history characters, matching the versioned Retrieval API contract.
Older visible turns remain on screen but are not silently sent past that
bounded context.

The client also carries up to 20 unique, previously returned structured source
references. This lets a later question refer to labels such as `Source 1`
without asking the model to infer what that label meant. Every request,
history turn, assistant history turn, and service response uses an opaque
64-hex-character identity.

Source labels are stabilized across the active chat. A document already shown
as `Source 1` keeps that label if it appears again. A newly returned document
that arrives with a response-local label already used in the chat receives the
next unused `Source N` label before it is displayed or carried into a later
request. Citation identities and document identities are not changed.

## Answer and source behavior

The UI accepts only the exact versioned response envelope. An answered result
contains one ordered sequence of citation-bearing segments, and every segment
citation must resolve to one returned source excerpt. The UI presents:

- the segments as flowing citation-bearing prose with compact inline source labels;
- only the cited complete structural sections or units in the selected turn;
- collapsible source cards with display name, class, continuous selectable
  source excerpts in structural order, unobtrusive page information, and no
  retrieval-enrichment prefixes or visible chunk boxes;
- the catalog document key and self-declared identifier, when present; and
- the last answered request's measured context tokens remaining above the
  composer.

Each expanded source card keeps `View full document` above its cited section
so the control remains visible before long source text. The control performs a
separate deterministic read-only request and
attaches a collapsible, progressively loaded reconstructed-text viewer beneath
the response that opened it. It does not call Gemma, alter conversation
context, retain the body in `sessionStorage`, or expose the original PDF.
All content is rendered as ordinary React text. HTML injection is not used.

## Health behavior

`/api/live` reports that the web process responds. `/api/ready` is successful
only when the loopback Retrieval API reports ready. The readiness response is
content-free and does not expose dependency identities or topology.

`/api/dependencies` exposes only `available` or `unavailable` for Gemma and
Nomic. The right-rail Model connections card displays each service state. The
endpoint never exposes credentials, URLs, response bodies, database state,
paths, or exceptions.

## Failure behavior

The proxy rejects an invalid media type, oversized request, malformed request,
invalid upstream envelope, or unavailable Retrieval API with a small safe
error. Its outer request deadline spans the Retrieval API's bounded sequential
model workflow. An outer deadline reports a request timeout; a connection or
transport failure reports the Retrieval API as unavailable. Neither condition
returns raw exceptions or upstream response bodies. The browser keeps the
current transcript and displays the safe failure message as an assistant turn
so the operator can retry without losing the conversation.
