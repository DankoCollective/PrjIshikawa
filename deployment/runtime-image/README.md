# Generic Node/Next runtime image

This source builds one application-free Linux AMD64 runtime image containing
Node.js 24.22.1, Next.js 16.4.3, React 19.2.9, React DOM 19.2.9, and the exact
transitive dependency graph in `package-lock.json`. A checksum-pinned npm
11.21.1 archive performs the dependency installation. The older npm and Yarn
copies bundled in the base image are never executed. No package manager or its
nested dependency tree exists in the flattened final runtime filesystem.

The image deliberately contains no application source, application
configuration, corpus, credential, database state, target-host state, or
generated `.next` output. Applications are supplied as read-only mounts at
runtime. Writable build output belongs in an independently bounded tmpfs at
`/opt/nextjs/.next`.

The assembly stage is pinned to the Linux AMD64 manifest digest for the official
`node:24.22.1-bookworm-slim` image. The build entrypoint verifies all direct
runtime versions, updates Bookworm timezone data to exact version
`2026e-0+deb12u1`, verifies npm's official archive with pinned SHA-256
`dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b`,
removes every package-manager copy, flattens the final filesystem, requires
native Linux AMD64 execution, exports one Docker archive, and records its
checksum and image identity. The generated CycloneDX SBOM
combines the exact installed JavaScript inventory with the Debian package
inventory from the built image; the license record binds JavaScript
declarations and each Debian package's in-image copyright-file path.
