# Ishikawa Nomic Chunk Embedding Acceptance

## Status

The operator-executed Script `28` result is accepted. The exact Script `27`
candidate set was measured and embedded through the pinned direct Nomic vLLM
path, returned to the control workstation, and independently validated.

## Accepted identities

```text
f29b7d727d8955a482ce3b3c4ae8a0c2e939cfc7c5c941e4c89db48ecc8c05ca  Script 28 receipt
5876c94380421741227f1bcaa494490158c1c83aeb5f54b39e894e9356b0f14d  measured embedding artifact
9e995789f6af145ed0589664a04730c87ea9ce58705bdd8186e1c5f9c0a873ef  artifact checksum sidecar
fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3  embedding-space identity
9a552140cfc816c2b91de95b0672f4a950fd943d7a802e946e4f3886e9edfb36  embedding-set digest
```

The artifact contains 125 records and is 1,994,919 bytes.

## Accepted result

- The exact pinned model, tokenizer, mean-token pooling, document prefix,
  768-vector dimension, unchanged-vector rule, and cosine space passed.
- Exact total input sizes ranged from 10 to 57 tokens. Zero inputs exceeded
  the initial 512-token target or the 2,048-token service ceiling.
- The service and tokenizer counts agreed for every batch.
- Every vector was finite and nonzero. The observed repeat maximum absolute
  delta was `5.96046448e-08`, below the frozen `1e-5` tolerance.
- The local evaluator revalidated all candidate mappings, submitted-input
  digests, token-accounting records, vector dimensions and norms, embedding
  identities, artifact identity, and set digest.
- The Nomic API key came only from the operator's attended prompt and was not
  logged, copied, or retained. Raw text and vectors were not logged.
- The Nomic service was already active and was left active. Target temporary
  files were removed and the SSH master closed cleanly.

## Boundary

This accepts token measurement and embedding creation for the six-document
synthetic corpus. It does not publish chunks, write PostgreSQL, qualify
retrieval quality, process organizational content, or complete org-lab target
qualification. The artifact remains non-publishable with
`pipeline_writer_integration_pending` until the next integration gate passes.

