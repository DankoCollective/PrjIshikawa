# Ishikawa v1.3.1 Footer Fallback Hotfix

This attended hotfix prevents an incomplete or document-specific footer from
blocking normalization. Such footers continue through Ishikawa's existing
generic recurring-furniture path. A fully recognized footer with conflicting
organization, policy, or page evidence still fails closed.

It replaces only `application/python/ishikawa/document_footer.py`. It does not
read or change corpus files, configuration, PostgreSQL, credentials, services,
or model endpoints.

Run from the extracted hotfix directory:

```bash
bash ./apply-hotfix --apply
```

Success ends with:

```text
SCRIPT RESULT
ishikawa_v1_3_1_footer_fallback_hotfix=pass
```
