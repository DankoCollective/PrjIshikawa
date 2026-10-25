# Danko Lab Operating Reference

## Purpose

This is the shared, non-secret operating reference for people and agents
working in Danko Lab. It consolidates the accepted lab topology, hardware
roles, installed product surfaces, common ports, and operating cautions that
were previously spread across project phases and product repositories.

Use this document for orientation. Use each product's operator guide for an
actual command or change. A recorded installation or accepted posture is not
proof that a process is running now.

Snapshot date: `2026-10-25`.

## Accuracy And Safety Rules

- Treat the addresses below as the accepted topology baseline, not a
  substitute for a live interface, listener, route, or DHCP check.
- DNS is not assumed. Use an accepted IP address until name resolution has
  been deliberately proved for the operation.
- Most application and model listeners are intentionally bound to loopback.
  Reach them through the product's accepted local, SSH-forward, or explicitly
  approved LAN path; do not broaden a listener merely for convenience.
- Installed, active, enabled-at-boot, and accepted are different states.
  Check all four when the distinction matters.
- Remote contact and state-changing work remain operator-attended and require
  current authorization. A hostname, key, alias, or prior successful run does
  not grant standing authority.
- Keep API keys, bearer tokens, passwords, private keys, private documents,
  prompts, responses, vectors, database dumps, MAC addresses, and full
  environment captures out of Git and ordinary reports.
- Stage and review public packages on `DankoSurface`, record advisories and
  checksums, carry the exact bytes, verify them again on the target, and
  install only from the verified carried set.
- Before a mutation, inventory the complete affected surface and identify the
  rollback source. Do not repair only the first observed blocker.

## Systems And Role Bindings

| System | Accepted address baseline | Hardware / OS identity | Primary lab role |
| --- | --- | --- | --- |
| `DankoSurface` | Target address `10.0.0.13`; current temporary Wi-Fi evidence observed `10.0.0.153` | ARM64 Surface Laptop, Windows operator workstation with WSL | Bastion and operator console, Git workspace, artifact staging authority, Postman/client surface, SSH and RDP origin |
| `00Danko` | `10.0.0.12` | NVIDIA DGX Spark, NVIDIA GB10 Grace Blackwell, ARM64, 20 CPU cores, 128 GB LPDDR5x unified memory, DGX OS / Ubuntu 24.04 family | AI workstation; Docker, vLLM model runtimes, and Dalton |
| `ChiefDanko` | `10.0.0.15` | Ubuntu 24.04, `amd64`, AMD CPU | Certificate, secret, identity, API-management, and control authority host |
| `EmceeDanko` | `10.0.0.16` | Ubuntu 24.04, `amd64`, Intel CPU | Application/API host and current application qualification host; temporary database duties where explicitly selected |
| `BankoDanko` | `10.0.0.17` | Ubuntu 24.04, `amd64`, Intel CPU | Intended dedicated database host; do not assume a database workload has been promoted here |

`DankoSurface` address caution: `10.0.0.13` is the selected target address.
The current network remains too inconsistent to enforce that identity, and a
later read-only inventory observed temporary Wi-Fi traffic from
`10.0.0.153`. Wait for the Ubiquiti network and reservation path to be
operational before treating `.13` as live. Until then, inspect the active
Windows adapters and the source address observed by the destination before
writing a source-address rule.

Canonical WSL repository root on `DankoSurface`:

```text
/mnt/g/DankoRepos/
```

The normal Linux administrator account used in the documented lab workflows
is `danko`. Exact SSH identities and their private-key paths remain local
operator configuration and are not recorded here.

## `00Danko` Compute Surface

### Base platform

- Docker Engine is the selected container runtime. Docker Desktop is not the
  target runtime on `00Danko`.
- NVIDIA AI Workbench is part of the DGX Spark platform and is configured as a
  target/remote location rather than installed as an ordinary project
  dependency.
- NVIDIA Sync is available for the operator workflow. Local IP addressing is
  preferred where Windows name discovery is unreliable.
- The model and Dalton services below are operator-controlled. Their accepted
  service posture is boot-disabled.

### vLLM container services v2.5

| Profile | Unit / container | Loopback endpoint | Served model | Accepted consumer posture |
| --- | --- | --- | --- | --- |
| Gemma | `vllm-gemma.service` / `vllm-gemma` | `127.0.0.1:8000` | `google/gemma-4-26B-A4B-it` | Installed; normally active with Nomic; boot-disabled |
| Nomic | `vllm-nomic.service` / `vllm-nomic` | `127.0.0.1:8001` | `nomic-ai/nomic-embed-text-v1.5` | Installed; normally active with Gemma; boot-disabled; 768-dimensional embeddings |
| Qwen | `vllm-qwen.service` / `vllm-qwen` | `127.0.0.1:8002` | `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` | Installed and operator-selectable; normally inactive; boot-disabled |

Dedicated locked service identities are `svc-vllm-gemma`,
`svc-vllm-nomic`, and `svc-vllm-qwen`. They receive model-read access through
`vllm-runtime-readers`; approved human runtime operations are mediated through
`vllm-admins` and a narrow sudo policy. The accounts are not login accounts
and are not Docker administrators.

Use the installed wrappers, not raw `systemctl start`, because the wrappers
validate capacity, configuration, images, models, credentials, readiness,
model behavior, logs, and containment:

```bash
sudo /usr/local/sbin/vllm-status gemma
sudo /usr/local/sbin/vllm-status nomic
sudo /usr/local/sbin/vllm-status qwen
sudo /usr/local/sbin/start-vllm <gemma|nomic|qwen>
sudo /usr/local/sbin/stop-vllm <gemma|nomic|qwen>
sudo /usr/local/sbin/stop-vllm all
sudo /usr/local/sbin/vllm-logs tail <gemma|nomic|qwen>
```

The immutable installed site definition is under `/etc/ai-runtime/vllm/`.
Gemma's operator-mutable next-start reasoning toggle is in
`/etc/ai-runtime/vllm/vllm-container-services-runtime-options.json`. Do not
edit the generated systemd units or place keys in command arguments.

### Dalton

Dalton is the authenticated model-transport authority in front of the native
vLLM APIs. It is not a model and does not replace the native vLLM services.

| Surface | Accepted value |
| --- | --- |
| Unit | `dalton.service` |
| Service identity | locked non-login `svc-dalton` |
| Human operator group | `dalton-admins` |
| Listener | `127.0.0.1:18080` |
| Configuration | `/etc/dalton/dalton-site-config.toml` |
| Protected state | `/var/lib/dalton/` |
| Operator broker | `/usr/local/sbin/dalton-admin` |
| Accepted posture | active and boot-disabled; verify before use |

Routine checks and lifecycle commands:

```bash
sudo dalton-admin config validate
sudo dalton-admin service status
sudo dalton-admin service start
sudo dalton-admin service stop
sudo dalton-admin service restart
```

Caller bearer tokens and Dalton's separate upstream Gemma/Nomic keys have
different purposes. Do not substitute one for the other. Token creation,
rotation, upstream-key rotation, logging mode, and protected log access are
privileged `dalton-admin` operations; consult the Dalton authority guide
before using them.

## `ChiefDanko` Authority And Control Surface

| Component | Unit / endpoint | Role and posture |
| --- | --- | --- |
| step-ca | `step-ca.service`, `127.0.0.1:9000` | Lab certificate authority; protected by locked `svc-step-ca` identity and authority-admin controls |
| OpenBao | `openbao.service`, `127.0.0.1:8200` | Secret and PKI authority; TLS, Raft storage, audit with raw logging disabled, static auto-unseal; accepted active and boot-enabled |
| WSO2 Identity Server | `wso2-is.service`, HTTPS `9443` in the current canonical layout | Identity/OIDC surface; operator-managed and not assumed active merely because installed |
| WSO2 API Manager | `wso2-apim.service`, HTTPS `9444` with the same-host offset layout | API-management surface; operator-managed and not assumed active merely because installed |
| PostgreSQL | host PostgreSQL service | Supports the accepted WSO2 data path on this host |
| GNOME Remote Desktop | `gnome-remote-desktop.service`, `10.0.0.15:3389` in the accepted reference proof | Current RDP reference implementation for the lab |

`svc-step-ca`, `svc-openbao`, `svc-wso2-is`, and `svc-wso2-apim` are service
identities, not human logins. Authority material is held under protected
system paths such as `/etc/svc-authority/` and `/var/lib/svc-authority/`; do
not move it into a human home or repository.

OpenBao's bootstrap/break-glass posture, PKI issuers, policies, audit,
snapshots, and WSO2 integrations are deliberately more constrained than an
ordinary development service. Use the Phase 12 current-path documents before
operating them.

## `EmceeDanko` Application Surface

### Anderson

- Anderson v1 is a package-local, on-demand application, not a managed
  service and not a boot-autostart workload.
- Default listener: `127.0.0.1:1384`.
- Dalton is its only accepted model-transport boundary.
- Its attended Anderson/Dalton/Gemma qualification remains a distinct product
  gate; an installed or buildable package does not imply release acceptance.

### Ishikawa

- Ishikawa v1.2 is preserved while v1.3 is qualified side by side.
- Ishikawa v1.3 passed the disposable EmceeDanko gate with 486 native tests
  and 60/60 synthetic frontier cases; attended target-side human UI
  acceptance remains the next product gate at this snapshot.
- The Chat UI is an on-demand container at `127.0.0.1:3000`.
- The Retrieval API is a native user service. Its portable packaged default
  remains `127.0.0.1:1384`; the selected EmceeDanko deployment override is
  `127.0.0.1:8384` so Anderson retains `1384`.
- PostgreSQL 16 with pgvector is the durable runtime source of truth at
  `127.0.0.1:5432`.
- Ingestion is a one-shot command, not a service.
- Ishikawa creates no Linux user, group, service account, or sudo rule. Its
  user units and stack remain boot-disabled.

For EmceeDanko human review, configure both Ishikawa YAML profiles for port
`8384`: the deployment profile's Retrieval API port and web retrieval URL,
and the Retrieval API service profile's default port. Keep Anderson on
`127.0.0.1:1384`. Inventory both ports before either launch.

The earlier demo wrapper used `127.0.0.1:8080`. Treat that as historical
unless a current inventory proves the service and listener are intentionally
present.

## `BankoDanko` Database Surface

`BankoDanko` is the reserved dedicated database-role host. The topology does
not itself prove that a current database, schema, role, or application has
been promoted there. Before database work, inventory the host, PostgreSQL
version and cluster names, listeners, storage, roles, backups, and consuming
applications. Do not repoint a client based only on the role label.

## Port And Collision Reference

| Host | Port | Expected owner | Exposure posture |
| --- | --- | --- | --- |
| `00Danko` | `8000` | Gemma vLLM | loopback |
| `00Danko` | `8001` | Nomic vLLM | loopback |
| `00Danko` | `8002` | Qwen vLLM | loopback |
| `00Danko` | `18080` | Dalton | loopback in the accepted baseline |
| `ChiefDanko` | `9000` | step-ca | loopback |
| `ChiefDanko` | `8200` | OpenBao | loopback |
| `ChiefDanko` | `9443` | WSO2 Identity Server | host HTTPS listener when active |
| `ChiefDanko` | `9444` | WSO2 API Manager | host HTTPS listener when active |
| `ChiefDanko` | `3389` | GNOME Remote Desktop | lab RDP listener in the accepted proof |
| `EmceeDanko` | `1384` | Anderson | loopback; reserved for Anderson |
| `EmceeDanko` | `8384` | Ishikawa Retrieval API | loopback; selected deployment override |
| `EmceeDanko` | `3000` | Ishikawa Chat UI | loopback |
| `EmceeDanko` | `5432` | PostgreSQL | loopback for the accepted Ishikawa layout |

SSH-forward ports such as `18000` or `18001` are operator-session choices,
not permanent service identities. Always inspect both ends of a forward and
do not infer the remote service from the local forwarded port alone.

## Fast Read-Only Inventory

Run only on a host you are currently authorized to inspect:

```bash
hostnamectl
uname -m
ip -brief address
ip route
ss -H -ltnp
systemctl --failed
systemctl list-unit-files --type=service
df -h
free -h
```

On `00Danko`, add:

```bash
nvidia-smi
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo /usr/local/sbin/vllm-status gemma
sudo /usr/local/sbin/vllm-status nomic
sudo /usr/local/sbin/vllm-status qwen
sudo dalton-admin config validate
sudo dalton-admin service status
```

On `EmceeDanko`, verify port ownership before launching an application:

```bash
ss -H -ltnp '( sport = :1384 or sport = :8384 or sport = :3000 or sport = :5432 )'
systemctl --user status ishikawa-retrieval-api.service --no-pager
```

Do not capture raw `ps e`, `/proc/*/environ`, decrypted credentials, or
unfiltered journals in routine diagnostics.

## Normal Work Path

1. Read this file and the selected product's agent context, runbook, and
   operator guide.
2. Confirm the intended host by hostname, address, OS, and architecture.
3. Inspect current services, listeners, capacity, and boot posture before
   assuming recorded state is still live.
4. Verify local artifacts, advisories, licenses, manifests, and checksums
   before target contact.
5. Use one operator-attended command that performs preflight, the bounded
   action, end-to-end verification, cleanup, and a standalone final result.
6. Retain only sanitized reports. Keep credentials and protected workload
   content outside the repository.
7. Update this reference in all repositories that carry it when a lab role,
   accepted address, installed control surface, or collision changes.

## Source And Product Authorities

This consolidation was derived from these durable local sources:

- `Prj00Danko/docs/00_project_posture/` and early setup phases for the DGX
  Spark hardware, base OS, Docker, AI Workbench, Sync, and operator workflow;
- `Prj00DankoDeux/phase-00-project_posture/` for the frozen role and product
  posture;
- `Prj00DankoDeux/phase-12-authority-services-logging/docs/LAB_TOPOLOGY.md`
  and current Phase 12 paths for lab addresses and authority services;
- `Prj00DankoDeux/phase-25-switch-danko_lab-docker/` for the accepted vLLM
  container-service surface;
- `Prj00DankoDeux/phase-26-dalton/` for Dalton's current service, authority,
  and operator contracts;
- `Prj00DankoDeux/phase-23-remote-desktop-access/` for the RDP boundary;
- the root control surfaces in `PrjAnderson` and `PrjIshikawa` for current
  product posture on `EmceeDanko`.

When this summary conflicts with a newer frozen product decision or a fresh
read-only inventory, stop and reconcile the document before mutation.
