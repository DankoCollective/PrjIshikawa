# Poppler Utilities Security Review — Ubuntu 24.04 ARM64

## Scope

- Review date: 2026-10-21
- Development host: Ubuntu 24.04 LTS, ARM64
- Source: Ubuntu `noble-updates` and `noble-security`
- Selected package: `poppler-utils` `24.02.0-1ubuntu9.10`
- Simulated native closure: five packages, with no recommended packages added:
  `libnspr4`, `libnss3`, `libopenjp2-7`, `libpoppler134`, and `poppler-utils`

Local APT policy exposed `24.02.0-1ubuntu9.10` as the current candidate from
both `noble-updates` and `noble-security`. The installation command must pin
that reviewed version and the exact simulated dependency versions; it must not
run `apt update` or accept a different candidate silently.

## Ubuntu Security Evidence

Ubuntu reports the following Noble fixes in the selected package lineage:

- CVE-2026-93314: fixed in `24.02.0-1ubuntu9.10`.
- CVE-2026-10118: fixed in `24.02.0-1ubuntu9.9`.
- CVE-2025-52885: fixed in `24.02.0-1ubuntu9.8`.
- CVE-2025-52886: fixed in `24.02.0-1ubuntu9.5`.
- CVE-2024-56378: fixed in `24.02.0-1ubuntu9.2`.
- CVE-2024-6239: fixed in `24.02.0-1ubuntu9.1`.

Primary references:

- https://ubuntu.com/security/CVE-2026-93314
- https://ubuntu.com/security/CVE-2026-10118
- https://ubuntu.com/security/CVE-2025-52885
- https://ubuntu.com/security/CVE-2025-52886
- https://ubuntu.com/security/CVE-2024-56378
- https://ubuntu.com/security/CVE-2024-6239
- https://ubuntu.com/security/cves?package=poppler

## Decision

The current Ubuntu-native candidate is accepted for the DankoSurface
development ingestion run. This is not an evergreen approval and does not
replace the separate advisory review and offline artifact capture required for
an org-lab deployment package.
