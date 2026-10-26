# Runtime license boundary

The runtime image uses the official Node.js Debian Bookworm slim base. Node.js
is distributed under its project license and the base operating-system files
retain their package license metadata. The image's JavaScript dependency
license inventory is generated from the exact npm lock during image assembly.

Primary license sources:

- <https://github.com/nodejs/node/blob/main/LICENSE>
- <https://www.debian.org/legal/licenses/>
- the `license` fields and package tarball identities in `package-lock.json`

The generated license inventory covers the exact JavaScript graph, installed
Debian package inventory, and final runtime tools. It records and hashes this
in-image runtime license file:

- Node.js 24.22.1 (`MIT`): `/usr/local/LICENSE`

npm 11.21.1 is a checksum-pinned build tool only and is absent from the
flattened distributed image, including its license and dependency tree. The
older npm and Yarn copies bundled in the base are not executed and are also
absent from the distributed image.

Each Debian record identifies the copyright file retained inside the image.
The combined CycloneDX SBOM and license inventory must be reviewed before the
runtime archive is promoted. This record is not a substitute for that review.
