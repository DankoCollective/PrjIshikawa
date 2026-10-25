# Native PostgreSQL Installation Preflight Diagnostic-Trap Repair

## Second Operator Run

The corrected operator-executed Script `08` rerun also blocked safely.

- report:
  `native_postgresql_installation_preflight_20261019T040313Z_5w0ido.txt`;
- report SHA-256:
  `a26280559850c154594a8ec4b32a6a57cdd8ed828749796cc9b337edca4842e4`;
- report size: `2250` bytes and `25` lines;
- Script `08` SHA-256:
  `f51aae05eaa67a2c11827e174f1020e6bebbdd40cefd5fd2fb966e58ae48f755`;
- executed neutral helper SHA-256:
  `d97adb70e2288a13cef23d03a52e7042d2f9a804ee5b9202ead86e392302b2c5`.

The target identity and payload checksum gates passed. Apt returned exit code
`100`, but the helper's inherited `ERR` trap intercepted that expected
nonzero result at the simulation command before the bounded classifier could
inspect it. The wrapper recorded one block marker, removed all target
temporary files, and closed its SSH master successfully.

No package was downloaded or installed. No database, service, or
configuration changed.

## Repair

The apt simulation now runs as the condition of an explicit Bash `if`. Bash
does not invoke the `ERR` trap for a command whose status is being tested by
that conditional. The helper therefore captures apt's status and, when it is
nonzero, emits the intended bounded diagnostic class plus hashes of the
discarded stdout and stderr. Raw apt output is still not retained.

This is a helper control-flow correction only. The accepted bundle, package
set, target, read-only apt invocation, and mutation boundary did not change.
Subsequent package-control review identified the underlying hard JIT
virtual-package conflict. The same Script `08` command is no longer the next
gate and must not be rerun against this bundle.
