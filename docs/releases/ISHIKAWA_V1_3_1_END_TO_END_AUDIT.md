# Ishikawa v1.3.1 end-to-end black-corpus audit

Date: 2026-10-28

## Outcome

The earlier Poppler and footer archives are rejected as carry artifacts. They
were incomplete corrections. The audit produced one cumulative seven-file
correction:

`ishikawa-v1.3.1-black-corpus-final-update.tar.gz`

SHA-256:

`821338d38d364a0c3864d5379a5b53b37d75a6110b3cb9661c25c373fe06fd73`

That archive is an internal rollup input, not the final Tech carry. Script 15
must apply it to the exact accepted v1.3.1 ancestor while assembling the final
application archive, regenerate every dependent identity, and publish one outer
deployment archive plus its adjacent checksum. A fresh target must never need
the outer package and a separate hotfix. The real Tech ingestion/publication
canary remains required before target acceptance.

## Audited path

The review covered the repository's installer and carry controls, native
prerequisites, schema and roles, operator configuration, PDF extraction,
normalization, structural chunking, embeddings, atomic publication,
relationship processing, retrieval, routing, evidence packing, generation and
citation validation, document reconstruction, HTTP transport, UI lifecycle,
service lifecycle, update, rollback, cleanup, and release packaging.

The audited implementation inventory contained 124 relevant Python, shell,
JavaScript, YAML, and service files and approximately 17,851 core lines. Static
review was combined with executable regression and exact-artifact proof; line
count alone is not treated as qualification.

## Corrections included in the cumulative update

The update atomically replaces exactly seven installed files and retains exact
pre-update bytes for rollback:

1. `scripts/capture-pdf-extraction-observations.py`
2. `application/python/ishikawa/document_control.py`
3. `application/python/ishikawa/document_footer.py`
4. `application/python/ishikawa/normalization.py`
5. `application/python/ishikawa/artifact_pipeline.py`
6. `application/python/ishikawa/live_document_stage.py`
7. `application/python/ishikawa/installed_ingestion.py`

The resulting behavior:

- qualifies compatible Poppler capability without one-host package revisions;
- retains repeatability proof without archiving a duplicate extraction tree;
- uses a two-hour upper bound for the changed-document batch;
- treats credentials as protected transport values without a private strength
  rule;
- uses generic normalization for incomplete or unsupported headers/footers;
- removes only lines proven to be recognized footer components;
- still rejects complete conflicting header/footer identities;
- recognizes recurring `Page N of M` furniture; and
- preserves the safe failed-stage reason through installed ingestion.

The update does not change source PDFs, operator metadata, PostgreSQL contents,
schema, retrieval ranking, model endpoints, service configuration, or UI bytes.

## Executable evidence

The exact corrected source passed:

- 506 discovered application tests;
- the real artifact adapter into one atomic committed publication batch;
- shell syntax checks across tracked operator and deployment scripts;
- repository diff whitespace validation; and
- 17 active deployment and lifecycle harnesses covering attended startup,
  carry assembly, the deployment entrypoint, native application/package
  handling, native prerequisite inventory, runtime-image handling, stack
  lifecycle, candidate staging, corrected promotion, and requalification.

The update lifecycle then passed all five supported states:

1. pristine v1.3.1 install;
2. the partially updated state already possible on Tech;
3. idempotent rerun;
4. pre-mutation refusal of unknown target bytes; and
5. forced post-publication verification failure with exact rollback of all
   seven files.

The final emitted archive passed its adjacent checksum, internal
`SHA256SUMS`, shell syntax validation, Python compilation, and an independent
fresh extraction. The archive is emitted only after the application and update
lifecycle gates pass in the same build.

## Active and superseded paths

The final corrected v1.3.1 application/runtime path is Scripts 12 through 15
and the portable deployment entrypoint. Script 13 supersedes the original
Script 10 promotion path. Scripts 14 and 15 supersede the original Script 11
package path. The current cumulative update supersedes all earlier v1.3.1
Poppler, header, and footer archives.

Scripts and receipts for the original v1.3 and initial v1.3.1 paths remain
historical evidence. Their frozen byte identities and hardcoded historical
test counts must not be rewritten to imitate the current source tree, and they
must not be selected for a new Tech action.

## Boundaries and permanent follow-up

The local audit did not contact Tech, protected black-corpus contents, accepted
databases, or model services. Therefore the first real Tech ingestion remains
the required external canary. That target run must use the one cumulative
candidate above; a new deterministic failure blocks and returns to source
review rather than producing another isolated patch.

Permanent corrections—including operator CSV handling, document-key contract,
source-root selection, OCR/mixed scans, family profiles, clarification
continuity, citation overflow, credential policy, canonical administration,
configuration drift coverage, artifact-profile registry, and self-contained
release test inventory—remain mandatory in
`docs/roadmap/ISHIKAWA_V1_3_2_CLARIFICATION_CONTINUITY.md`.

## Final-package rollup gate

The stable final-package builder is required to prove all of the following in
one run:

1. the ancestor application SHA-256 is the accepted v1.3.1 identity;
2. the cumulative update SHA-256 is the identity recorded above;
3. exactly seven enumerated payload paths are overlaid and no update state is
   carried;
4. application, source-manifest, SBOM, security-review, receipt, classified
   package-manifest, and outer-checksum identities are rebound coherently;
5. the application verifier and portable deployment verifier pass after a
   fresh extraction;
6. the exact extracted deployer passes both direct (`8000/8001`) and forwarded
   (`18000/18001`) endpoint profiles; and
7. no standalone hotfix archive is present or required in the final package.

This gate passed twice from independent assembler runs and produced identical
bytes. The final single-carry identities are:

- outer archive: `ishikawa-v1.3.1-linux-amd64.tar`;
- outer archive SHA-256:
  `0a48c9865ebafa8b54990f969c336498289c650d5f27a4ee595c51056edaaccc`;
- rolled application archive SHA-256:
  `25c70e4217d0b92117b52542439910657529f7441671965c8e61c879bfb9109d`;
- cumulative correction SHA-256:
  `821338d38d364a0c3864d5379a5b53b37d75a6110b3cb9661c25c373fe06fd73`;
  and
- runtime-image archive SHA-256:
  `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1`.

An independent fresh extraction passed the portable verifier with release
state `deployment_ready`. The receipt records `single_carry_rollup=true`, the
outer archive contains no standalone hotfix/update payload, and a fresh target
requires only the outer archive and its adjacent checksum.
