# Runtime license boundary

The runtime image uses the official Node.js Debian Bookworm slim base. Node.js
is distributed under its project license and the base operating-system files
retain their package license metadata. The image's JavaScript dependency
license inventory is generated from the exact npm lock during image assembly.

Primary license sources:

- <https://github.com/nodejs/node/blob/main/LICENSE>
- <https://www.debian.org/legal/licenses/>
- the `license` fields and package tarball identities in `package-lock.json`

The generated license inventory covers both the exact JavaScript graph and the
installed Debian package inventory. Each Debian record identifies the
copyright file retained inside the image. The combined CycloneDX SBOM and
license inventory must be reviewed before the runtime archive is promoted.
This record is not a substitute for that review.
