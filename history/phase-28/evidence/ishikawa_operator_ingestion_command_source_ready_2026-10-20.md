# Ishikawa Operator Ingestion Command Source Ready

Date: 2026-10-20

Operator-executed Script `75` is accepted. Its report SHA-256 is
`bc8ec1f4ef5b4221222fbe2ddf837eebf71e0e3fce9bf400f172557896da1980`
and its configured-live-runtime artifact SHA-256 is
`36c3e880092cab03e179814a9efa6b4cb94b85c77778951002745d856d236376`.

Script `76` implements and locally qualifies the operator-ingestion control
plane. The application module:

- loads and exactly validates the class registry, document catalog, and one
  incremental ingestion manifest through the restricted YAML loader;
- reads current published document state and the durable catalog-key set;
- creates one deterministic add, revise, reprocess, reuse, or retire plan;
- makes `--validate-only` incapable of invoking the document producer or
  PostgreSQL writer;
- submits only add, revise, and reprocess documents to an injected producer;
- never submits reuse or retirement entries for document production;
- sends quarantined plans to the accepted writer with no prepared documents,
  allowing a quarantine record but no publication;
- never invokes the producer or writer for a rejected plan; and
- writes mode-`0600` protected reports with bounded terminal output.

The local source gate passed all 279 tests plus four dedicated orchestration
scenarios. Validation-only made zero producer and writer calls. Incremental add
made one producer and one writer call. Reuse and quarantine made zero producer
calls. The gate used injected non-networking database, producer, and writer
ports; it contacted no target, PostgreSQL server, Nomic endpoint, or Gemma
endpoint and read no credential.

Validated source identities:

- wrapper:
  `4f0139d892170f752e470f7038483b02ad9717980523910430bc3acd6e81e113`
- application module:
  `776cfdf5607da9b9fbe11b0afd96dea8b80ba3887062b6636229859491c62857`
- tests:
  `5519a5060498be64c887b461f573ffe9d55deba18949f511b80fdbf5357fde53`
- evaluator:
  `41555d03e586017d921368407641a58cb09997be38f060f410ecc34b93d6a19e`
- deterministic qualification artifact:
  `177ce380f01093343a29c4515661ab4b1be737b093fe2ad7b669221f6d054d7e`

Script `76` is source-ready but not yet operator-accepted. Its next accepted
boundary will connect this control plane to the native document producer and
native PostgreSQL deployment adapter without changing its orchestration
contract.
