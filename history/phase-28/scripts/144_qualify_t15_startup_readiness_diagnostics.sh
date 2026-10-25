#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify frozen T15 component-specific startup readiness diagnostics.
#
# Mental model:
#   Bind the exact T15 decision and changed sources, run all native tests,
#   verify portable documentation, and prove that operator startup identifies
#   configuration, storage, PostgreSQL, Gemma, and Nomic states while the
#   public /ready response remains only ready or not-ready.
#
# Inputs or prerequisites:
#   The local Ishikawa working source. No runtime credential is required.
#
# Outputs:
#   One content-free local report and checksum-bound qualification receipt.
#   No target, database, model, service, package, or accepted release changes.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/144_qualify_t15_startup_readiness_diagnostics.sh --run

usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Qualify and retain the local evidence.' \
    '  --validate-only Run the same checks without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_ishikawa_documentation.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-t15-readiness-diagnostics"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/t15-readiness-diagnostics"
readonly EXPECTED_TEST_COUNT=385

readonly -a BOUND_FILES=(
  "$DECISIONS|6dbfbffbe3d904fc5c19d8df513049ededc678d1d4c8276aea04bad14522bbb2|decision_list"
  "$PRODUCT_ROOT/application/python/ishikawa/readiness.py|a981395b8ce299d1a3c263a64454b5d550dfc7a504c17831dc34ec29bdd7c442|readiness_source"
  "$PRODUCT_ROOT/application/python/ishikawa/retrieval_command.py|c1c215b7652f6550353893a567b0f63e587056f8660ca152bb698e96af40e2ea|retrieval_command_source"
  "$PRODUCT_ROOT/application/python/ishikawa/http_listener.py|69f09d1f86518099bf65982ec78d6b92434fe89d8a1df0a5a1b2b0fc4cc08769|http_listener_source"
  "$PRODUCT_ROOT/scripts/ishikawa-stack|33d765c76aac1f4a1ca0176505bfc55e64b21103a9531dda07a207cd65c71cdd|stack_command"
  "$PRODUCT_ROOT/tests/test_readiness.py|98685e33a77cdafae9098c9591439d77e52474d92a59fb11910af2aa5d83a03b|readiness_tests"
  "$PRODUCT_ROOT/tests/test_retrieval_command.py|63ac58a34942cda6d79159ec3fe781e4853a8df4462e63af85404438455a4235|retrieval_command_tests"
  "$PRODUCT_ROOT/tests/test_service_lifecycle.py|73eb59cf1cf1664a623ebaa75b4c0db74db764b61bcea068745bc14184af16fa|lifecycle_tests"
  "$PRODUCT_ROOT/tests/test_http_listener.py|ab86cb3901b0015f47f3211113e6ac6312279ccd61cab3fd0377b5fa41e94110|http_listener_tests"
  "$PRODUCT_ROOT/docs/SERVICE_OPERATIONS.md|ed6c9d7a92a35153b892f074a9ddbda656ef7b52d9fa7c0fc9672727cc24e479|service_operations"
  "$PRODUCT_ROOT/docs/STACK_CONTROL.md|16648d7be8c90cee7c3e8c1bb2971cc8796079e1ed4ea88769223ed76811ac5d|stack_control"
  "$PRODUCT_ROOT/docs/COMMAND_SHEET.md|e5d602af42654002556107528839a63f81c0d0257ff6579c68eb8a66011a39a5|command_sheet"
  "$PRODUCT_ROOT/packaging/README.md|c0f699293e96227476ec074bb832b5b5ae69c0a8702ceececdeeb9cd946be802|package_readme"
  "$EVALUATOR|da4a10f75f7698c0bb3d7888d9bdb0376e69207a89723266cf4757dc68a19216|documentation_evaluator"
  "$TEST_RUNNER|092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7|test_runner"
)

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_144_t15_readiness=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_144_t15_readiness=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash chmod date dirname grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_144_t15_readiness=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

for binding in "${BOUND_FILES[@]}"; do
  path="${binding%%|*}"
  remainder="${binding#*|}"
  expected="${remainder%%|*}"
  label="${remainder##*|}"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_144_t15_readiness=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'script_144_t15_readiness=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
done

grep -Eq '^\| `T15` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_144_t15_readiness=blocked;reason=t15_not_frozen\n' >&2
  exit 2
}
bash -n "${BASH_SOURCE[0]}" "$PRODUCT_ROOT/scripts/ishikawa-stack" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$PRODUCT_ROOT/application/python/ishikawa/readiness.py" \
  "$PRODUCT_ROOT/application/python/ishikawa/retrieval_command.py" \
  "$PRODUCT_ROOT/tests/test_readiness.py" \
  "$PRODUCT_ROOT/tests/test_retrieval_command.py" \
  "$PRODUCT_ROOT/tests/test_service_lifecycle.py" \
  "$EVALUATOR"

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-144.XXXXXX)"
report_path=''
artifact_path=''
checksum_path=''
artifact_committed=false
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/t15_readiness_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/t15_readiness_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-144.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_output="$work_root/native-tests.txt"
if PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_output" 2>&1; then
  test_status=0
else
  test_status=$?
fi
(( test_status == 0 )) || {
  printf 'script_144_t15_readiness=blocked;reason=native_test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s;raw_output_retained=false\n' \
    "$(sha256sum "$test_output" | awk '{print $1}')" "$(stat -c '%s' "$test_output")" >&2
  exit 1
}
grep -Fq "Ran $EXPECTED_TEST_COUNT tests" "$test_output" || {
  printf 'script_144_t15_readiness=blocked;reason=native_test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_output" || {
  printf 'script_144_t15_readiness=blocked;reason=native_test_pass_marker_absent\n' >&2
  exit 1
}

documentation_receipt="$work_root/documentation.json"
documentation_output="$work_root/documentation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --docs-root "$PRODUCT_ROOT/docs" \
  --config-root "$PRODUCT_ROOT/config/templates" \
  --command-root "$PRODUCT_ROOT/scripts" \
  --python-root "$PYTHON_ROOT" \
  --output "$documentation_receipt" >"$documentation_output" || {
    printf 'script_144_t15_readiness=blocked;reason=documentation_regression\n' >&2
    exit 1
  }
grep -Fxq 'documentation_qualification=pass' "$documentation_output" || {
  printf 'script_144_t15_readiness=blocked;reason=documentation_pass_marker_absent\n' >&2
  exit 1
}

stack_source="$PRODUCT_ROOT/scripts/ishikawa-stack"
[[ "$(grep -Fc -- '--check-readiness' "$stack_source")" == 2 ]] || {
  printf 'script_144_t15_readiness=blocked;reason=stack_diagnostic_count_invalid\n' >&2
  exit 1
}
for required_marker in \
  'postgresql=blocked;' \
  'gemma=blocked;nomic=pass' \
  'retrieval_readiness_preflight_failed' \
  'retrieval_readiness_failed_after_preflight' \
  '_health_response("ready" if ready else "not-ready")'; do
  grep -Fq "$required_marker" \
    "$PRODUCT_ROOT/tests/test_readiness.py" \
    "$PRODUCT_ROOT/scripts/ishikawa-stack" \
    "$PRODUCT_ROOT/application/python/ishikawa/http_listener.py" || {
      printf 'script_144_t15_readiness=blocked;reason=diagnostic_contract_missing\n' >&2
      exit 1
    }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
decision_sha256="$(sha256sum "$DECISIONS" | awk '{print $1}')"
source_manifest="$work_root/source.sha256"
for binding in "${BOUND_FILES[@]}"; do
  path="${binding%%|*}"
  printf '%s  %s\n' "$(sha256sum "$path" | awk '{print $1}')" "${path#"$REPO_ROOT"/}"
done >"$source_manifest"
source_manifest_sha256="$(sha256sum "$source_manifest" | awk '{print $1}')"
documentation_sha256="$(sha256sum "$documentation_receipt" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_t15_startup_readiness_diagnostics' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256;source_manifest_sha256=$source_manifest_sha256" \
    "native_tests=$EXPECTED_TEST_COUNT;failures=0;errors=0;documentation=pass" \
    'components=configuration,storage,postgresql,gemma,nomic;public_ready_detail=false' \
    'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false' \
    'script_144_t15_readiness_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/t15_readiness_${timestamp}_XXXXXX.txt")"
artifact_path="$(mktemp "$ARTIFACT_ROOT/t15_readiness_${timestamp}_XXXXXX.json")"
checksum_path="$artifact_path.sha256"

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$artifact_path" "$script_sha256" "$decision_sha256" \
  "$source_manifest_sha256" "$documentation_sha256" "$EXPECTED_TEST_COUNT" <<'PY'
import json
import sys
from pathlib import Path

output, script, decision, manifest, documentation, tests = sys.argv[1:]
receipt = {
    "accepted_release_changed": False,
    "component_states": [
        "configuration",
        "storage",
        "postgresql",
        "gemma",
        "nomic",
    ],
    "credential_read": False,
    "database_contact": False,
    "decision_sha256": decision,
    "documentation_receipt_sha256": documentation,
    "model_contact": False,
    "native_test_count": int(tests),
    "package_changed": False,
    "public_ready_detail": False,
    "receipt_schema_version": 1,
    "script_sha256": script,
    "source_manifest_sha256": manifest,
    "target_contact": False,
}
Path(output).write_text(
    json.dumps(receipt, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum "$(basename -- "$artifact_path")" >"$(basename -- "$checksum_path")"
)

{
  printf '%s\n' \
    'purpose=qualify_t15_startup_readiness_diagnostics' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256;source_manifest_sha256=$source_manifest_sha256" \
    "native_tests=$EXPECTED_TEST_COUNT;failures=0;errors=0;documentation=pass;documentation_receipt_sha256=$documentation_sha256" \
    'readiness_components=configuration,storage,postgresql,gemma,nomic' \
    'operator_diagnostic=component_pass_or_blocked;public_ready_response=unchanged_content_free' \
    'retrieval_changed=false;ranking_changed=false;embedding_changed=false;database_changed=false;model_behavior_changed=false' \
    'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false' \
    "artifact=$(basename -- "$artifact_path");artifact_sha256=$(sha256sum "$artifact_path" | awk '{print $1}')" \
    'script_144_t15_readiness=pass'
} | tee "$report_path"
chmod 0600 "$report_path" "$artifact_path" "$checksum_path"
artifact_committed=true
