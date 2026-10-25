# Native PostgreSQL Advisory Source Outage Repair

## Result

The operator-resumed Script `06` run reused the accepted target metadata,
downloaded and hash/size-verified all nine target-required packages, and
completed inert file and license inspection. All nine packages have captured
copyright material. No package was installed or transferred.

The run then stopped while Ubuntu's public security-notice pages returned HTTP
`504` and `502`. The local report is:

- `native_postgresql_package_capture_20261019T032047Z_11oJ9l.txt`;
- SHA-256
  `9c373e3810eaed22bdbc93cc341147536ab27dd8b36d9b8654486e2db7c5e514`;
- 1,512 bytes and 18 lines.

The package artifacts remain intact and reusable. No bundle was sealed, and
installation remains unauthorized.

## Repair

Public advisory retrieval is now removed from Script `06` and deferred to a
separate review gate. Package capture therefore cannot hang or fail on the
availability of the Ubuntu website. Script `06` records all three sources as
deferred, seals the checksum-bound package bundle with
`pass_with_advisory_sources_pending`, keeps installation unauthorized, and
requires separate advisory review before transfer or installation.

Current Script `06` SHA-256:

`3971b9d863cca3477a72cfa2360a0738779c0b26d73568dafb8ce228f82ad3ae`

The no-network resume validation passes with 98 dependency records, nine
target-required downloads, 43,797,374 download bytes, and no target contact.
The next operator run reuses and re-verifies all nine existing package files.

## Operator Command

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh \
  --resume-latest
```
