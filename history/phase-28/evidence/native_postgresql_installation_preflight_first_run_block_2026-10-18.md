# Native PostgreSQL Installation Preflight First-Run Block

## Result

The first operator-executed Script `08` run safely blocked during the local
package simulation on EmceeDanko.

- report:
  `native_postgresql_installation_preflight_20261019T035947Z_SHqy9n.txt`;
- report SHA-256:
  `3edbc6e2fa0fff22bd7304037fd0946cd042a10b882d7f8ffea02829bf9a3d5c`;
- report size: `2227` bytes and `25` lines;
- Script `08` SHA-256:
  `f51aae05eaa67a2c11827e174f1020e6bebbdd40cefd5fd2fb966e58ae48f755`;
- neutral helper SHA-256:
  `cbb508d378a3ce7daa4fe4f3c592c7ce88e59b49207017108b711215775bfe11`.

Authentication, target hostname/OS/architecture validation, and the temporary
payload checksum gate passed. The target helper then returned
`apt_simulation_failed`. The wrapper recorded zero pass markers and one block
marker, removed the complete target temporary directory, and closed its SSH
master successfully.

No package was installed or downloaded. No database was initialized and no
service or configuration changed.

## Repair

The failed invocation added `--no-download` to a simulation. EmceeDanko's
earlier accepted apt simulation used `apt-get -s` without that redundant
option. Simulation mode itself performs no download or installation. The
helper now uses the previously proven invocation shape with exact local `.deb`
arguments and retains `--no-install-recommends` plus disabled locking.

The helper also now emits only bounded diagnostic classification, exit code,
and stdout/stderr hashes if apt rejects a future simulation. It still does not
retain raw apt output, paths, package contents, or target stderr.

The accepted bundle, package set, target, and mutation boundary did not
change. The same Script `08` command is the next gate after refreshed local
validation.
