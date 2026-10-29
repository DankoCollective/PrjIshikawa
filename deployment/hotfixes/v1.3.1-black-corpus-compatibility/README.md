# SUPERSEDED — Ishikawa v1.3.1 black-corpus compatibility hotfix

Do not build, carry, or apply this archive. It was incomplete and is retained
only as historical evidence. It is superseded by
`../v1.3.1-black-corpus-final/` and the exact candidate identified in
`docs/releases/ISHIKAWA_V1_3_1_END_TO_END_AUDIT.md`.

It makes three bounded corrections without changing the corpus, database,
configuration, services, retrieval ranking, or credentials:

- accepts the coherent Poppler toolset installed on the qualified Tech host;
- sends incomplete or document-specific footers through generic furniture
  normalization while keeping complete conflicting footers fail-closed;
- sends complete-looking headers with an empty/image-only department cell
  through generic normalization while keeping complete conflicting headers
  fail-closed.

Apply from the extracted directory on Tech:

```bash
bash ./apply-hotfix --apply
```

The command is idempotent. It accepts either the original v1.3.1 files or the
already-applied Poppler correction, retains the exact pre-update files, applies
all replacements together, rolls every target back if verification fails, and
prints one standalone final result.
