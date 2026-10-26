# Ishikawa native prerequisite inventory

This kit captures a bounded, read-only inventory for an Ubuntu AMD64 host
before Ishikawa native dependencies are acquired or installed. It does not
update package metadata, download or install packages, initialize PostgreSQL,
change services, inspect application content, contact model endpoints, or read
credentials.

Verify the kit before execution:

```bash
sha256sum --check --strict SHA256SUMS
```

Run it as the intended non-root operator. Select a new protected temporary
output directory that can be removed after its files have been carried back:

```bash
bash ./inspect-native-prerequisites \
  --expected-os-version 26.04 \
  --expected-architecture amd64 \
  --postgresql-port 5432 \
  --retrieval-port 1384 \
  --web-port 3000 \
  --output-dir /tmp/ishikawa-native-prerequisite-inventory
```

The output directory contains a content-free host summary, exact installed
and candidate package facts, and a checksum manifest. Missing packages or
inaccessible Docker metadata are recorded as inventory facts; they do not
authorize a repair or installation. Review package provenance and security
advisories before any package payload is downloaded.

The optional expected-hostname check is transient. Retained output contains
no hostname, account, address, device serial, credential, document content, or
environment dump. It is limited to OS/architecture, bounded capacity,
runtime/package identity and health, Docker-image presence, planned-listener
counts, and PostgreSQL service posture.

The three port values are planned target inputs, not fixed lab assumptions.
Set them to the ports selected for the target deployment before inventory.

