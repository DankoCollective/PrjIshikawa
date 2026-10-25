# SSH Connection Reuse Standard

## Purpose

This file records the repository-neutral SSH connection reuse pattern for operator-run wrappers that perform more than one SSH or SCP action against the same target. Product history may record where the pattern was first used, but active scripts must depend only on this standard.

Use it for operator-facing scripts that perform more than one SSH/SCP action against the same target host, such as copy payload, run payload, copy result, verify result, or cleanup.

The goal is to avoid repeated SSH key passphrase prompts while keeping the existing function-specific SSH key discipline.

## What Changed

The canonical pattern uses OpenSSH ControlMaster multiplexing:

- `ControlMaster=auto` lets the first SSH/SCP connection create a reusable control connection.
- `ControlPersist=300` keeps that authenticated connection alive briefly after the first command exits.
- Later `scp` or `ssh` commands with the same `ControlPath` reuse the connection instead of asking for the key passphrase again.
- A cleanup trap closes the control connection at script exit.

This does not remove the SSH key passphrase. It only reuses the authenticated connection for a short, script-owned window.

## Canonical Pattern

Use a script-unique control path under `/tmp`, not inside the repo. Keep it short: Unix domain socket paths have small platform limits, and long script labels plus `%r@%h:%p` can break `ssh`/`scp` before any remote command runs.

```bash
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
ssh_control_path="/tmp/<short-script-prefix>-${timestamp}-%C"

ssh_common_args=(
  -o ControlMaster=auto
  -o ControlPath="$ssh_control_path"
  -o ControlPersist=300
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
)
ssh_tty_args=(-tt "${ssh_common_args[@]}")
scp_args=("${ssh_common_args[@]}")

if [[ -n "$TARGET_IDENTITY_FILE" ]]; then
  ssh_common_args+=(-i "$TARGET_IDENTITY_FILE" -o IdentitiesOnly=yes)
  ssh_tty_args+=(-i "$TARGET_IDENTITY_FILE" -o IdentitiesOnly=yes)
  scp_args+=(-i "$TARGET_IDENTITY_FILE" -o IdentitiesOnly=yes)
fi

cleanup() {
  ssh "${ssh_common_args[@]}" -O exit "$TARGET_SSH" >/dev/null 2>&1 || true
}
trap cleanup EXIT
```

Then use the shared argument arrays for all same-target actions:

```bash
scp "${scp_args[@]}" "$local_payload" "$TARGET_SSH:$remote_payload"

ssh "${ssh_tty_args[@]}" "$TARGET_SSH" \
  "bash '$remote_payload' '$expected_hostname' '$expected_ip'"
```

The `-O exit` option must appear before the SSH target:

```bash
ssh "${ssh_common_args[@]}" -O exit "$TARGET_SSH"
```

Putting `-O exit` after the target turns it into a remote command argument and does not close the control master.

## Optional Front-Loaded Prompt

If a script has a long local stage before the first remote command, it may front-load the passphrase prompt near the beginning:

```bash
ssh "${ssh_common_args[@]}" -Nf "$TARGET_SSH"
```

Only use this when it improves the operator experience. The cleanup trap still must close the control connection with `-O exit`.

## Rules

- Keep function-specific SSH identities. Do not use ControlMaster to blur key purpose or host purpose.
- Use one short control path per script run and target host.
- Prefer OpenSSH `%C` in the path. `%C` hashes the connection tuple and avoids long socket names while still making the path host/user/port/key-context specific.
- Do not embed long script names, full repository names, or raw `%r@%h:%p` in the control socket path.
- Do not store control sockets in the repo or under `local/`.
- Do not write SSH key passphrases, passwords, tokens, or private key material to reports.
- Keep `ControlPersist` short, normally `300` seconds or less, unless a script documents a narrow reason.
- Close the control connection in `trap cleanup EXIT`.
- When front-loading a master with `-o ControlMaster=yes`, use `-Nf` without another `-M`. Adding `-M` after that setting selects confirmation mode on the checked OpenSSH client. Validate launch arguments locally with `ssh -G`, then verify the actual owned master with `ssh -O check` before dependent transfers.
- Record master creation, readiness, copy/run, and cleanup results. Preserve non-secret error classifications when transport fails; do not discard the only diagnostic evidence or treat a successful master launch as proof that subsequent sessions work.
- For multi-host scripts, create a separate control path per host.
- Do not use this pattern to bypass approval, sudo, mTLS, OpenBao, WSO2, package/advisory, or artifact-carry gates.

## When Not To Use It

Skip this pattern for a single one-shot SSH command unless repeated prompts are expected.

Do not keep a control connection open across unrelated scripts. Each script should own and close its own control connection.
