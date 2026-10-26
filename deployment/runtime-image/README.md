# Generic Node/Next runtime image

This source builds one application-free Linux AMD64 runtime image containing
Node.js 24.22.1, Next.js 16.4.3, React 19.2.9, React DOM 19.2.9, and the exact
transitive dependency graph in `package-lock.json`.

The image deliberately contains no application source, application
configuration, corpus, credential, database state, target-host state, or
generated `.next` output. Applications are supplied as read-only mounts at
runtime. Writable build output belongs in an independently bounded tmpfs at
`/opt/nextjs/.next`.

The base image is pinned to the Linux AMD64 manifest digest for the official
`node:24.22.1-bookworm-slim` image. The build entrypoint verifies all direct
runtime versions, builds only Linux AMD64, exports one Docker archive, and
records its checksum and image identity. The generated CycloneDX SBOM combines
the exact npm lock with the installed Debian package inventory from the built
image; the license record binds npm declarations and each Debian package's
in-image copyright-file path.
