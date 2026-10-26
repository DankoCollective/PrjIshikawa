# Ishikawa v1.3.1 Application Build Evidence

## Result

Date: 2026-10-26 America/Los_Angeles

Corrected Script 08 completed on the frozen native Ubuntu 24.04 AMD64
EmceeDanko build host. It verified the retained Script 07 image, ran the full
application build gates, returned only the external application handoff,
verified that handoff independently, published it atomically to the candidate
artifact lane, and removed the private target transfer.

`script_08_v1_3_1_application_build=pass`

## Exact identities

- Application archive: `ishikawa-v1.3.1.tar.gz`
- Application archive SHA-256:
  `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69`
- Application archive size: `283046` bytes
- Source-manifest SHA-256:
  `fda594e21ee21c1be94ce5e173b227123c1893d4ac78f8edf5a27b501448d9fa`
- Runtime image ID:
  `sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298`
- Runtime archive SHA-256:
  `af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f`
- Content-free retained Script 08 report SHA-256:
  `e23e832d1d80c3ac7d1e87e68549f3256ce1f5a4e04c4368a6c9141db983c4f5`

## Passed gates

- Native Python suite: 486 tests.
- JavaScript suite: 17 tests.
- Production Next.js build against the exact generic AMD64 image.
- Two clean deterministic application assemblies with identical archive
  bytes.
- Fresh extraction, bundled verification, and fresh installation.
- Coding-standard, corpus-absence, and historical-repair checks.
- Application SBOM and Apache-2.0 license identity.
- Exact runtime-image retention: Script 08 did not rebuild or change the
  Script 07 image.
- Verified artifact return, atomic candidate publication, and private remote
  transfer cleanup.

## Boundary and next gate

The build contacted no database, model endpoint, service, credential, corpus,
or boot setting. It does not constitute human acceptance of v1.3.1 and does
not authorize stable carry promotion.

Numbered Script 09 is the next operator-facing gate. It requalifies this exact
application archive with the exact Script 07 image on EmceeDanko in an
isolated side-by-side production runtime, obtains separate human acceptance,
and cleans up the candidate without changing the accepted v1.3 installation
or corpus-v3 database.
