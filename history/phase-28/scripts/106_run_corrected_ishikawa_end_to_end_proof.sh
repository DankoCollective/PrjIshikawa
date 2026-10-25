#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind the accepted runtime correction to Ishikawa's complete end-to-end
#   proof, then delegate to the already-qualified proof runner.
#
# Mental model:
#   Prove that the corrected application archive was installed without state
#   loss, bind the exact complete proof implementation, and run that proof
#   unchanged. The target receives only the proof runner's neutral payload.
#
# Inputs or prerequisites:
#   Accepted runtime-candidate promotion evidence, pre-forwarded model ports,
#   attended target access, and the four runtime credentials requested by the
#   complete proof.
#
# Outputs:
#   The complete proof's local report and artifact plus one lineage marker
#   showing that the proof ran after the accepted runtime correction.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/106_run_corrected_ishikawa_end_to_end_proof.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Run the corrected end-to-end proof.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate the complete proof without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PROOF_SCRIPT="$SCRIPT_DIR/104_run_first_ishikawa_end_to_end_proof.sh"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-runtime-candidate-promotion/runtime_candidate_promotion_20261021T040140Z_ovnNdq.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/runtime-candidate-promotion/runtime_candidate_promotion_20261021T040140Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly PROOF_SCRIPT_SHA256='3fa2a383bfdd11c1bc65cb6496eb4760309a652d9b1fecd5dd944cf0a67f18a5'
readonly ACCEPTED_REPORT_SHA256='adb9b987cc28a3c28291868c166b3afd83b5248a98f0aa57334167f3d6769615'
readonly ACCEPTED_ARTIFACT_SHA256='9cca07bc3ec0e6929e7a6cb42850ea4b15199ec06d0e00181705290025f7c98f'
readonly ACCEPTED_CHECKSUM_SHA256='0c702230ce3175daa65fd98e80a0f51c3428fb4fe663b702db83373ae56611c0'
readonly CORRECTED_ARCHIVE_SHA256='bb3eb2c33e6380d04e32fa474a7592260604d2ccef0c3cdb9181db116965e1b0'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'

mode=''
delegate_arguments=()
while (( $# > 0 )); do
  case "$1" in
    --run|--validate-only)
      [[ -z "$mode" ]] || { printf 'script_106_corrected_runtime_proof=blocked;reason=mode_invalid\n' >&2; exit 2; }
      mode="$1"
      delegate_arguments+=("$1")
      shift
      ;;
    --target|--expected-hostname|--expected-os-version|--identity-file)
      (( $# >= 2 )) || { printf 'script_106_corrected_runtime_proof=blocked;reason=argument_missing\n' >&2; exit 2; }
      delegate_arguments+=("$1" "$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'script_106_corrected_runtime_proof=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ -n "$mode" ]] || { printf 'script_106_corrected_runtime_proof=blocked;reason=mode_missing\n' >&2; exit 2; }

for required in awk bash basename dirname grep sed sha256sum; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_106_corrected_runtime_proof=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
for file in "$PROOF_SCRIPT" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_106_corrected_runtime_proof=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_106_corrected_runtime_proof=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$PROOF_SCRIPT" "$PROOF_SCRIPT_SHA256" proof_script
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" accepted_artifact
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" accepted_checksum
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_106_corrected_runtime_proof=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }

for fact in \
  "new_archive_sha256=$CORRECTED_ARCHIVE_SHA256" \
  "module_identity=$CORRECTED_MODULE_SHA256;connection_autocommit=true;atomic_writer_boundary=explicit_transaction" \
  'operator_configuration=preserved;corpus=preserved;application_state=preserved;candidate_retained=true' \
  'database_changed=false;service_changed=false;container_changed=false;model_contact=false;credential_read=false;port_forwarding_changed=false' \
  'ishikawa_runtime_candidate_promotion=pass' \
  'script_105_runtime_candidate_promotion=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_106_corrected_runtime_proof=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$PROOF_SCRIPT"
printf '%s\n' \
  'purpose=run_complete_proof_after_runtime_correction' \
  "accepted_runtime_promotion_sha256=$ACCEPTED_REPORT_SHA256;corrected_archive_sha256=$CORRECTED_ARCHIVE_SHA256" \
  "corrected_module_sha256=$CORRECTED_MODULE_SHA256;proof_script_sha256=$PROOF_SCRIPT_SHA256" \
  'runtime_correction=accepted;configuration_preserved=true;corpus_preserved=true;database_preserved=true'

set +e
bash "$PROOF_SCRIPT" "${delegate_arguments[@]}"
proof_exit_code=$?
set -e
if (( proof_exit_code != 0 )); then
  printf 'script_106_corrected_runtime_proof=blocked;reason=complete_proof_failed;exit_code=%s\n' "$proof_exit_code" >&2
  exit "$proof_exit_code"
fi

if [[ "$mode" == --validate-only ]]; then
  printf 'script_106_corrected_runtime_proof_source=pass\n'
else
  printf 'script_106_corrected_runtime_proof=pass;next_gate=assemble_single_ishikawa_v1_deployment_package\n'
fi
