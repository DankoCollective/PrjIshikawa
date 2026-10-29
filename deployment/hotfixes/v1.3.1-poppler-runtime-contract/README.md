# Ishikawa v1.3.1 Poppler Runtime-Contract Hotfix

## Purpose

This attended hotfix removes the obsolete host-specific Poppler version
allowlist from the PDF extraction stage. It records the installed package and
tool identities, requires `pdfinfo` and `pdftotext` to report one coherent
version, and leaves real extraction and repeatability checks authoritative.

## Scope

The hotfix replaces exactly
`scripts/capture-pdf-extraction-observations.py` in an accepted Ishikawa v1.3.1
installation. It does not read or change corpus files, configuration,
PostgreSQL, credentials, services, or model endpoints.

Verify the carried archive before extraction, then run from the extracted
hotfix directory:

```bash
sha256sum -c ../ishikawa-v1.3.1-poppler-hotfix.tar.gz.sha256
sha256sum -c SHA256SUMS
bash ./apply-hotfix --apply
```

Success ends with:

```text
SCRIPT RESULT
ishikawa_v1_3_1_poppler_hotfix=pass
```
