# Ishikawa native-prerequisite handoff

This handoff performs one read-only native-prerequisite inventory on an Ubuntu
AMD64 application host. It does not update package metadata, download or
install packages, initialize PostgreSQL, change services, inspect application
content, contact model endpoints, or read credentials.

Verify the handoff, then run its neutral command as the intended non-root
operator:

```bash
sha256sum --check --strict SHA256SUMS
bash ./run-native-prerequisite-inventory
```

The command requires Ubuntu `26.04` and Debian architecture `amd64`. It creates
one checksum-bound result archive and sidecar in `/tmp`, prints their exact
paths, and removes its private working directory. Carry both result files back
for review, then delete them from the target after acceptance.

