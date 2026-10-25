# Ishikawa Live Document Artifact Stage

The live document artifact stage is the single process boundary between the
incremental planner and the installed extraction, normalization, chunking,
tokenization, and document-embedding pipeline.

For each accepted `add`, `revise`, or `reprocess` batch, the stage writes one
mode-`0600` canonical request containing only the planner-selected document
keys, classes, relative source paths, source SHA-256 identities, action,
manifest identity, validation identity, and frozen method-profile identity.
It does not submit the entire corpus directory as work.

The stage invokes one absolute, regular, executable pipeline command without
a shell. Endpoint locations, model identity, batch size, request path, source
root, and protected workspace are explicit arguments. The Nomic credential is
supplied only through standard input and is never an argument, YAML value,
terminal value, or retained artifact.

The pipeline must return `normalized.json`, `chunks.json`, `embeddings.json`,
and one bounded `stage-result.json`. The result must bind all three files by
SHA-256 to the validation, manifest, method profile, and served model. Missing,
unexpected, mismatched, symlinked, or nonzero results fail closed with a
content-free reason. The producer independently validates the returned files
again before adapting or retaining them.

The installed command is `ishikawa-produce-artifacts`. Its exact internal
pipeline and cleanup behavior are defined in
`LIVE_DOCUMENT_PIPELINE_EXECUTABLE.md`; target execution remains a separate
qualification gate.
