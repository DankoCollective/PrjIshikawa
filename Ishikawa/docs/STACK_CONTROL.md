# Ishikawa stack control

## Boundary

`scripts/ishikawa-stack` is the explicit operator lifecycle command for the
complete local application. It accepts only `start`, `status`, or `stop`.
Nothing is started at boot, and the command does not install packages or
units, initialize or migrate PostgreSQL, edit configuration, ingest documents,
create model forwarding, or expose a non-loopback listener.

Required Gemma and Nomic port forwarding remains an external operator action.
The configured endpoints must already be reachable before `start`.

## Start order

`start` validates the installed configuration and final runtime shape before
changing state. It requires the native PostgreSQL cluster, Retrieval API, web
container, and all three configured ports to be stopped and unused. It then:

1. verifies PostgreSQL and the Retrieval API are not enabled at boot;
2. verifies the architecture-matching local Node 24/Next.js image;
3. requires the three protected credential variables without printing them;
4. starts native PostgreSQL and waits for `pg_isready`;
5. briefly imports only the three named credentials into the user service
   manager, starts the Retrieval API, and immediately removes the manager
   copies after the process receives them;
6. performs a content-free component readiness preflight that names
   configuration, storage, PostgreSQL, Gemma health, and Nomic health states;
7. waits for Retrieval API liveness and complete readiness;
8. starts one hardened web container as the installing operator's numeric
   UID/GID, with a read-only root filesystem, host networking, read-only source
   bind mounts, and one bounded writable tmpfs at `/opt/nextjs/.next`;
9. runs `next build` in that container, emits bounded build heartbeats,
   validates the generated build markers, and executes `next start` in the
   same container; and
10. waits for web liveness and readiness, records measured build size against
    the tmpfs bound, and then records the stack as ready.

Any failure rolls back every component started by that attempt. The owner-only
state record contains only its schema, owner, and lifecycle state.
Readiness diagnostics contain only component names and `pass` or `blocked`;
they never include credentials, paths, endpoint bodies, database values,
document content, or raw exceptions.

## Status and stop

`status` makes no changes. It reports `stopped`, `ready`, or `degraded` from
the managed state record, component states, and readiness endpoints. It never
reports credential values, response bodies, document content, or exception
text.

`stop` requires a valid managed state record and proceeds in reverse order:
web container, Retrieval API, then PostgreSQL. The web container is removed,
which deletes its ephemeral `.next` build so the next start rebuilds from the
validated external source. The command removes any remaining named
credential copies from the user service manager, verifies the components are
stopped, removes the state record, and confirms the boot-disabled posture.

## Commands

```text
scripts/ishikawa-stack start
scripts/ishikawa-stack status
scripts/ishikawa-stack stop
```
