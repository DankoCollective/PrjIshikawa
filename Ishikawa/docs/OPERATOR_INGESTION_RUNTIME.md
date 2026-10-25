# Ishikawa Operator-Ingestion Runtime

The operator-ingestion runtime is a one-shot command assembly, not a service.
It binds the accepted operator paths and method profile to four explicit
runtime dependencies:

- native PostgreSQL on the configured host and port, using role `rag_ingest`;
- the Nomic embedding and tokenization endpoint locations;
- a changed-document artifact stage; and
- protected retention of accepted producer artifacts.

`ingestion_dependencies.yaml` contains endpoint locations, model identity,
limits, database identity, and protected-environment variable names. It never
contains credential values. The Nomic credential is read only when the live
artifact stage invokes its provider. The PostgreSQL password is read only
when the ingestion command opens its connection.

The configured runtime fixes one class registry, document catalog, ingestion
manifest, source root, report root, and producer work root for an invocation.
This prevents the command from validating one manifest while producing from
another. Its only modes are `validate-only` and `publish`.

Assembly does not connect to PostgreSQL, call Nomic, process a PDF, mutate the
corpus, or retain source content. Those effects occur only after an explicit
operator execution. The concrete live artifact-stage implementation and its
retention policy are qualified independently from this assembly boundary.
