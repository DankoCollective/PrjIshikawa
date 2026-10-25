# Ishikawa Nomic Chunk Embedding Source Ready

## Status

Script `28` is source-ready after complete no-contact validation. Target Nomic
measurement and embedding remain `NOT RUN` until the operator executes the
published command.

## Bound inputs

```text
0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548  accepted Script 27 candidate artifact
18dcc83979426951b3bfa308ec3f756cdb4657cde1a21a3ef0d5a1a7f30d6661  accepted Script 27 receipt
2309ef678501275fcb74b976c30ad110439fc1958af4694a9438b077a106c9bf  accepted Nomic compatibility receipt
```

## Source identities

```text
6b6503be21b900504f9447e5306cf151fb21b534cd836d13305f8554908673a1  28_qualify_nomic_chunk_embeddings.sh
a47b395ec6838d50f3f19e2498b60a1751ea99c847c82b14889e80fe7e0e786f  qualify-chunk-embeddings
f9cd2297a2e95951c041d73074910b33bf5e594e3e3439fdb2770ac386c2a6e9  qualify_chunk_embeddings.py
8759e9f0e353f7ec6df83a8196dc6a9e75f07614d52eee91aa11e65323cff192  evaluate_chunk_embeddings.py
da77225fb9e6e414dd749a39159015b3de38cbf50ecba30c37d323df1f7e196a  embedding_qualification_checks.py
```

## No-contact proof

```text
target_contact=false;model_call=false;retained_artifact=false
base_tests=64;normalization_tests=13;chunking_tests=12;embedding_tests=8;failures=0;errors=0
script_28_embedding_source=pass
```

The neutral target payload contains only the target shell, self-contained
Python qualifier, and fully synthetic chunk candidates. It contains no phase,
gap, repository, agent, or lab terminology. The operator supplies the API key
through an attended terminal; the key is neither transferred nor retained.
The target output is content-free, and the wrapper validates all returned
token counts, identities, vectors, digests, and result facts locally before
retaining an artifact.

## Operator command

```bash
bash ./phase-28-apisachi-tokuli/scripts/28_qualify_nomic_chunk_embeddings.sh --run
```

Only `script_28_embedding=pass` accepts this gate.

