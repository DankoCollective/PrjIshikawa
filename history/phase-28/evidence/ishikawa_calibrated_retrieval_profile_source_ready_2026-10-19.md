# Ishikawa Calibrated Retrieval Profile Source Ready

Date: 2026-10-19

## Result

The operator froze the retrieval settings accepted by Script `37`. The
implementation now separates the chunk-method identity from a canonical
retrieval-profile identity, provides a restricted-YAML configuration surface,
uses the frozen settings as application defaults, and passes 90 local tests.

## Frozen identities

- chunk-method profile:
  `5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0`;
- calibrated retrieval profile:
  `33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7`.

## Operator acceptance

Script `38` passed all 90 tests and retained the local freeze receipt. It
performed no remote access, database access, model call, package change,
secret handling, or source-document read. The next gate is implementation of
the frozen relationship contract.
