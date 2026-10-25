#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise the Script 05 target helper through its complete disposable
#   candidate, database, ingestion, API, frontier, cleanup, and failure paths.
#
# Mental model:
#   Install the real checksum-bound v1.3 payload into an isolated HOME, retain
#   the real corpus archive and helper, and replace only external PostgreSQL,
#   model, ingestion, API, and frontier execution boundaries with deterministic
#   local doubles. Run the real helper through a pseudo-terminal so protected
#   credential entry and cleanup behavior are exercised.
#
# Inputs or prerequisites:
#   Current Script 01 and Script 03 handoffs and standard host test utilities.
#
# Outputs or artifact lane:
#   Temporary files under /tmp only; no network, target, or repository mutation.
#
# Usage:
#   bash ./deployment/tests/qualify-candidate-helper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/qualify-v1.3-candidate"
readonly generator="$repo_root/deployment/assets/create-corpus-v3-ingestion-config.py"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"
readonly corpus="$repo_root/local/artifacts/qualification-corpus-v3-current/qualification-corpus-v3.tar.gz"

last_output=''
last_result=''

fail() {
  if [[ -n "$last_output" && -s "$last_output" ]]; then
    printf '%s\n' 'QUALIFICATION HELPER OUTPUT' >&2
    tail -n 200 -- "$last_output" >&2 || true
  fi
  if [[ -n "$last_result" && -s "$last_result" ]]; then
    printf '%s\n' 'QUALIFICATION HELPER RESULT' >&2
    tail -n 80 -- "$last_result" >&2 || true
  fi
  printf '\nSCRIPT RESULT\nqualify_candidate_helper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

for file in "$helper" "$generator" "$application" "$corpus"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || fail input_unsafe
done
for command_name in awk chmod cp find ln mv python3 script sha256sum sort tar wc xargs; do
  command -v "$command_name" >/dev/null 2>&1 || fail "command_missing_${command_name}"
done
bash -n "$helper" || fail helper_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-qualify-helper-test.XXXXXX)"
model_pid=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$model_pid" =~ ^[0-9]+$ ]] && kill -0 "$model_pid" 2>/dev/null; then
    kill -TERM "$model_pid" 2>/dev/null || true
    wait "$model_pid" 2>/dev/null || true
  fi
  [[ "$test_root" == /tmp/ishikawa-qualify-helper-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/home/Documents/Ishikawa" \
  "$test_root/home/Documents/Ishikawa-before-v1.2" \
  "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" \
  "$test_root/bin" "$test_root/package" "$test_root/payload/database" \
  "$test_root/payload/native-tests/tests" \
  "$test_root/payload/native-tests/config/templates" \
  "$test_root/payload/native-tests/packaging/systemd"
tar -xzf "$application" -C "$test_root/package"
bash "$test_root/package/ishikawa-v1.3/application/install-ishikawa" \
  --install-root "$test_root/home/Documents/Ishikawa-v1.3" >/dev/null \
  || fail candidate_install_failed
cp -- "$corpus" \
  "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
(cd -- "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" \
  && sha256sum qualification-corpus-v3.tar.gz >qualification-corpus-v3.tar.gz.sha256)

awk '$2 ~ /^payload\// {sub(/^payload\//, "", $2); print $1 "  " $2}' \
  "$test_root/package/ishikawa-v1.3/application/SHA256SUMS" \
  >"$test_root/payload/candidate-SHA256SUMS"
[[ -s "$test_root/payload/candidate-SHA256SUMS" ]] || fail candidate_manifest_missing
cp -- "$generator" "$test_root/payload/create-corpus-v3-ingestion-config.py"
cp -- "$repo_root/Ishikawa/scripts/run-local-validation-tests.sh" \
  "$test_root/payload/native-tests/run-local-validation-tests.sh"
find "$repo_root/Ishikawa/tests" -maxdepth 1 -type f -name 'test_*.py' -print0 \
  | sort -z | xargs -0 -r cp -t "$test_root/payload/native-tests/tests/" --
cp -a -- "$repo_root/Ishikawa/tests/fixtures" \
  "$test_root/payload/native-tests/tests/fixtures"
find "$repo_root/Ishikawa/config/templates" -maxdepth 1 -type f -name '*.yaml' -print0 \
  | sort -z | xargs -0 -r cp -t "$test_root/payload/native-tests/config/templates/" --
find "$repo_root/Ishikawa/packaging/systemd" -maxdepth 1 -type f -print0 \
  | sort -z | xargs -0 -r cp -t "$test_root/payload/native-tests/packaging/systemd/" --
[[ "$(find "$test_root/payload/native-tests/tests" -maxdepth 1 -type f -name 'test_*.py' | wc -l | tr -d ' ')" == 41 ]] \
  || fail native_test_inventory_invalid

cp -- "$repo_root/Ishikawa/packaging/database/schema.sql" \
  "$test_root/payload/database/schema.sql"
test_schema_sha256="$(sha256sum "$test_root/payload/database/schema.sql" | awk '{print $1}')"
printf '%s\n' '#!/usr/bin/env bash' \
  "printf '%s\\n' 'ishikawa_schema_install=pass;schema_version=5;schema_sha256=${test_schema_sha256}'" \
  >"$test_root/payload/database/install-schema"
chmod 0700 "$test_root/payload/database/install-schema"
(cd -- "$test_root/payload/database" \
  && sha256sum install-schema schema.sql >SHA256SUMS)

printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import json, os, pathlib, sys' \
  'args = sys.argv[1:]' \
  'if args == ["--self-test"]:' \
  '    print("v1_3_complete_api_evaluator_self_test=pass")' \
  '    raise SystemExit(0)' \
  'if args and args[0] == "--validate-cases":' \
  '    print("v1_3_complete_api_case_set=pass;cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60;identity=" + "b" * 64)' \
  '    raise SystemExit(0)' \
  'if args and args[0] == "--run":' \
  '    if os.environ.get("ISHIKAWA_TEST_FRONTIER_FAIL") == "1":' \
  '        print("case_result=R-001;actual=temporarily_unavailable;expected=answered;returned=0/1;cited=0/1")' \
  '        print("v1_3_complete_api_evaluation=blocked;reason=case_failure")' \
  '        raise SystemExit(1)' \
  '    def value(flag): return args[args.index(flag) + 1]' \
  '    output = pathlib.Path(value("--output"))' \
  '    target = {"architecture": value("--expected-architecture"), "hostname": value("--expected-hostname"), "os_id": "ubuntu", "os_version": value("--expected-os-version")}' \
  '    summary = {"acceptance_gate": "pass", "case_count": 60, "contract_valid_count": 60, "expected_status_match_count": 60, "required_evidence_count": 60, "required_evidence_returned_count": 60, "required_evidence_cited_count": 60, "dependency_failure_count": 0}' \
  '    output.write_text(json.dumps({"artifact_kind": "ishikawa_v1_3_complete_api_qualification", "synthetic_content_only": True, "target": target, "summary": summary, "cases": [{} for _ in range(60)]}), encoding="utf-8")' \
  '    print("case_result=R-001;actual=answered;expected=answered;returned=1/1;cited=1/1")' \
  '    print("complete_api_cases=60;expected_status_matches=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0")' \
  '    print("v1_3_complete_api_evaluation=pass")' \
  '    raise SystemExit(0)' \
  'raise SystemExit(2)' \
  >"$test_root/payload/evaluate-frontier.py"
chmod 0700 "$test_root/payload/evaluate-frontier.py"
chmod 0700 "$test_root/payload/native-tests/run-local-validation-tests.sh"
(cd -- "$test_root/payload" \
  && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)

write_command() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$test_root/bin/$name"
  chmod 0700 "$test_root/bin/$name"
}
write_command hostname "printf 'EmceeDanko\\n'"
write_command uname "[[ \"\${1:-}\" == -m ]] && printf 'x86_64\\n'"
write_command systemctl "[[ \"\${1:-}\" == --user && \"\${2:-}\" == is-active ]] && printf 'active\\n'"
write_command ss 'case "$*" in *1385*|*65438*) exit 0 ;; *) printf "LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:1384 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:5432 0.0.0.0:*\\n" ;; esac'
write_command curl 'printf "%s" "${ISHIKAWA_TEST_CURL_STATUS:-200}"'
write_command initdb 'while (( $# )); do [[ "$1" == -D ]] && { mkdir -p -- "$2"; exit 0; }; shift; done; exit 2'
write_command pg_ctl 'exit 0'
write_command createdb 'exit 0'
write_command psql 'if [[ " $* " == *"ishikawa.verify-schema"* ]]; then if [[ "${ISHIKAWA_TEST_SCHEMA_FAIL:-0}" == 1 ]]; then printf "wrong\\n"; else printf "ishikawa_consolidated_schema_v5|%s|5\\n" "$(sha256sum "$ISHIKAWA_TEST_PAYLOAD_ROOT/database/schema.sql" | awk '\''{print $1}'\'')"; fi; elif [[ " $* " == *" -A "* ]]; then printf "30;150;786;943;157;943;%s;%s\\n" "${ISHIKAWA_TEST_RELATIONSHIP_RECORDS:-240}" "${ISHIKAWA_TEST_RELATIONSHIP_PAIRS:-90}"; else while IFS= read -r _line; do :; done; fi'
for name in initdb pg_ctl createdb psql; do
  mv -- "$test_root/bin/$name" "$test_root/bin/${name}.real"
  ln -s -- "${name}.real" "$test_root/bin/$name"
done

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
  '/usr/bin/cp "$@"' \
  'source_path=""; destination="${!#}"' \
  'for argument in "$@"; do [[ "$argument" == "$ISHIKAWA_TEST_CANDIDATE_ROOT/." ]] && source_path="$argument"; done' \
  'if [[ -n "$source_path" && "$destination" == */product/ ]]; then' \
  '  printf "%s\\n" "#!/usr/bin/env bash" "case \"\${1:-}\" in --validate-only) printf \"actions=add:30,reprocess:0,retire:0,reuse:0,revise:0\\\\n\" ;; --publish) if [[ \"\${ISHIKAWA_TEST_INGEST_FAIL:-0}\" == 1 ]]; then printf \"ishikawa_ingestion=blocked;reason=live_document_stage_document_embedding_endpoint_http_401\\\\n\"; exit 1; fi; printf \"ishikawa_ingestion=pass;exit_code=0\\\\n\" ;; *) exit 2 ;; esac" >"$destination/scripts/ishikawa-ingest"' \
  '  mv -- "$destination/scripts/ishikawa-retrieval-api" "$destination/scripts/ishikawa-retrieval-api.real"' \
  '  printf "%s\\n" "#!/usr/bin/env bash" "if [[ \"\${1:-}\" == --check-config ]]; then exec \"\$(dirname -- \"\$0\")/ishikawa-retrieval-api.real\" \"\$@\"; fi" "if [[ \"\${1:-}\" == --serve ]]; then trap \"exit 0\" TERM INT; while :; do sleep 1; done; fi" "exit 2" >"$destination/scripts/ishikawa-retrieval-api"' \
  '  chmod 0700 "$destination/scripts/ishikawa-ingest" "$destination/scripts/ishikawa-retrieval-api"' \
  'fi' >"$test_root/bin/cp"
chmod 0700 "$test_root/bin/cp"

printf '%s\n' \
  'import http.server, pathlib, sys' \
  'class Handler(http.server.BaseHTTPRequestHandler):' \
  '    def do_POST(self):' \
  '        length = int(self.headers.get("Content-Length", "0")); self.rfile.read(length)' \
  '        if self.headers.get("Authorization") == "Bearer nomic-invalid-test-key-012345678901234567890123":' \
  '            self.send_response(401); self.send_header("Content-Type", "application/json"); self.end_headers(); return' \
  '        body = b"{\"data\":[{\"embedding\":[1.0" + b",1.0" * 767 + b"],\"index\":0,\"object\":\"embedding\"}],\"model\":\"nomic-ai/nomic-embed-text-v1.5\",\"object\":\"list\",\"usage\":{\"prompt_tokens\":12,\"total_tokens\":12}}" if self.path == "/v1/embeddings" else b"{\"count\":3,\"max_model_len\":2048,\"tokens\":[1,2,3]}"' \
  '        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)' \
  '    def do_GET(self):' \
  '        body = bytes.fromhex("7b2264617461223a5b5d7d") if self.path == "/v1/models" else bytes.fromhex("7b22737461747573223a226f6b227d")' \
  '        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)' \
  '    def log_message(self, *args): pass' \
  'server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)' \
  'pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")' \
  'server.serve_forever()' >"$test_root/model-server.py"
python3 -B "$test_root/model-server.py" "$test_root/model-port" &
model_pid="$!"
for _attempt in {1..100}; do [[ -s "$test_root/model-port" ]] && break; sleep 0.05; done
[[ -s "$test_root/model-port" ]] || fail model_double_not_ready
model_port="$(<"$test_root/model-port")"

active_identity_before="$(stat -Lc '%d:%i' "$test_root/home/Documents/Ishikawa")"
rollback_identity_before="$(stat -Lc '%d:%i' "$test_root/home/Documents/Ishikawa-before-v1.2")"

run_helper() {
  local name="$1" frontier_fail="${2:-0}" curl_status="${3:-200}" ingest_fail="${4:-0}"
  local nomic_value="${5:-nomic-test-key-012345678901234567890123456789}"
  local schema_fail="${6:-0}"
  local relationship_records="${7:-240}" relationship_pairs="${8:-90}"
  local result="$test_root/payload/${name}-result.txt"
  local artifact="$test_root/payload/${name}-artifact.json"
  local output="$test_root/${name}.stdout"
  local command
  last_output="$output"
  last_result="$result"
  command="bash '$helper' --run --expected-hostname EmceeDanko --expected-os-version 24.04 --expected-architecture amd64 --candidate-root '$test_root/home/Documents/Ishikawa-v1.3' --corpus-input-root '$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs' --payload-root '$test_root/payload' --result-path '$result' --artifact-path '$artifact' --gemma-base-url 'http://127.0.0.1:$model_port' --nomic-base-url 'http://127.0.0.1:$model_port'"
  set +e
  printf '%s\n%s\n' 'gemma-test-key' "$nomic_value" \
    | HOME="$test_root/home" PATH="$test_root/bin:$PATH" \
      ISHIKAWA_TEST_CANDIDATE_ROOT="$test_root/home/Documents/Ishikawa-v1.3" \
      ISHIKAWA_TEST_FRONTIER_FAIL="$frontier_fail" \
      ISHIKAWA_TEST_CURL_STATUS="$curl_status" \
      ISHIKAWA_TEST_INGEST_FAIL="$ingest_fail" \
      ISHIKAWA_TEST_SCHEMA_FAIL="$schema_fail" \
      ISHIKAWA_TEST_RELATIONSHIP_RECORDS="$relationship_records" \
      ISHIKAWA_TEST_RELATIONSHIP_PAIRS="$relationship_pairs" \
      ISHIKAWA_TEST_PAYLOAD_ROOT="$test_root/payload" \
      script -qefc "$command" /dev/null 2>&1 | tr -d '\r' >"$output"
  helper_status="${PIPESTATUS[1]}"
  set -e
}

run_helper pass
(( helper_status == 0 )) || fail complete_lifecycle_failed
grep -Fxq '[INPUT REQUIRED] Gemma API key' "$test_root/pass.stdout" \
  || fail gemma_prompt_not_visible
grep -Fxq '[INPUT MODE] Hidden input is active. Paste or type the value, then press Enter.' "$test_root/pass.stdout" \
  || fail gemma_input_mode_not_visible
grep -Fq '[INPUT ACCEPTED] Gemma API key received.' "$test_root/pass.stdout" \
  || fail gemma_acceptance_not_visible
grep -Fxq '[INPUT REQUIRED] Nomic API key' "$test_root/pass.stdout" \
  || fail nomic_prompt_not_visible
grep -Fq '[INPUT ACCEPTED] Nomic API key received.' "$test_root/pass.stdout" \
  || fail nomic_acceptance_not_visible
grep -Fq 'state=pass;nomic_authenticated=true;embedding_contract=pass;tokenization_contract=pass' \
  "$test_root/pass.stdout" || fail nomic_authenticated_probe_missing
grep -Fxq 'qualify_v1_3_candidate=pass' "$test_root/pass.stdout" || fail pass_marker_missing
grep -Fxq 'ishikawa_v1_3_emceedanko_disposable_qualification=pass' "$test_root/payload/pass-result.txt" || fail result_contract_missing
grep -Fxq 'native_qualification=pass;tests=486' "$test_root/payload/pass-result.txt" \
  || fail native_result_contract_missing
grep -Fxq 'corpus_v3_ingestion=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;retrieval_scoring_only=157;embeddings=943;relationship_records=240;relationship_pairs=90' \
  "$test_root/payload/pass-result.txt" || fail corpus_inventory_result_contract_missing
[[ -f "$test_root/payload/pass-artifact.json" ]] || fail frontier_artifact_missing
grep -Fq 'state=pass;ingestion_configuration=created_on_target;documents=30' "$test_root/pass.stdout" \
  || fail target_manifest_generation_marker_missing
grep -Fq 'schema_contract=pass' "$test_root/pass.stdout" \
  || fail schema_contract_probe_missing
[[ ! -e "$test_root/home/Documents/Ishikawa-v1.3/config/ingestion/pending/qualification-corpus-v3.yaml" ]] \
  || fail candidate_was_mutated_by_manifest_generation

cp -- "$test_root/payload/native-tests/run-local-validation-tests.sh" \
  "$test_root/native-runner.saved"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "ERROR: test_forced_target_failure (test_target.TargetTests.test_forced_target_failure)" "FAILED (errors=1)" >&2' \
  'exit 1' >"$test_root/payload/native-tests/run-local-validation-tests.sh"
chmod 0700 "$test_root/payload/native-tests/run-local-validation-tests.sh"
(cd -- "$test_root/payload" \
  && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)
run_helper native-failure
(( helper_status != 0 )) || fail native_failure_accepted
grep -Fxq 'reason=target_native_tests_failed' \
  "$test_root/payload/native-failure-result.txt" || fail native_failure_reason_missing
grep -Fq 'failed_tests=ERROR_test_forced_target_failure' \
  "$test_root/native-failure.stdout" || fail native_failure_detail_missing
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/native-failure-result.txt" || fail native_failure_cleanup_not_proved
mv -- "$test_root/native-runner.saved" \
  "$test_root/payload/native-tests/run-local-validation-tests.sh"
(cd -- "$test_root/payload" \
  && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)

run_helper nomic-failure 0 200 0 'nomic-invalid-test-key-012345678901234567890123'
(( helper_status != 0 )) || fail nomic_failure_accepted
grep -Fxq 'reason=nomic_preflight_failed' \
  "$test_root/payload/nomic-failure-result.txt" || fail nomic_failure_reason_missing
grep -Fxq 'root_cause=nomic_embedding_embedding_upstream_http_error' \
  "$test_root/payload/nomic-failure-result.txt" || fail nomic_failure_root_cause_missing
grep -Fq 'nomic_preflight=blocked;stage=embedding;reason=embedding_upstream_http_error' \
  "$test_root/nomic-failure.stdout" || fail nomic_failure_marker_not_streamed
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/nomic-failure-result.txt" || fail nomic_failure_cleanup_not_proved

run_helper ingestion-failure 0 200 1
(( helper_status != 0 )) || fail ingestion_failure_accepted
grep -Fxq 'reason=ingestion_publication_failed' \
  "$test_root/payload/ingestion-failure-result.txt" || fail ingestion_failure_reason_missing
grep -Fxq 'root_cause=live_document_stage_document_embedding_endpoint_http_401' \
  "$test_root/payload/ingestion-failure-result.txt" || fail ingestion_failure_root_cause_missing
grep -Fq 'ishikawa_ingestion=blocked;reason=live_document_stage_document_embedding_endpoint_http_401' \
  "$test_root/ingestion-failure.stdout" || fail ingestion_safe_marker_not_streamed
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/ingestion-failure-result.txt" || fail ingestion_failure_cleanup_not_proved

run_helper schema-failure 0 200 0 'nomic-test-key-012345678901234567890123456789' 1
(( helper_status != 0 )) || fail schema_failure_accepted
grep -Fxq 'reason=installed_schema_contract_mismatch' \
  "$test_root/payload/schema-failure-result.txt" || fail schema_failure_reason_missing
grep -Fq 'Expected schema ledger ishikawa_consolidated_schema_v5|' \
  "$test_root/schema-failure.stdout" || fail schema_failure_detail_missing
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/schema-failure-result.txt" || fail schema_failure_cleanup_not_proved

run_helper relationship-record-failure 0 200 0 \
  'nomic-test-key-012345678901234567890123456789' 0 239 90
(( helper_status != 0 )) || fail relationship_record_mismatch_accepted
grep -Fxq 'reason=database_inventory_mismatch' \
  "$test_root/payload/relationship-record-failure-result.txt" \
  || fail relationship_record_mismatch_reason_missing
grep -Fq 'Expected corpus inventory 30;150;786;943;157;943;240;90; observed 30;150;786;943;157;943;239;90.' \
  "$test_root/relationship-record-failure.stdout" \
  || fail relationship_record_mismatch_detail_missing
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/relationship-record-failure-result.txt" \
  || fail relationship_record_mismatch_cleanup_not_proved

run_helper relationship-pair-failure 0 200 0 \
  'nomic-test-key-012345678901234567890123456789' 0 240 89
(( helper_status != 0 )) || fail relationship_pair_mismatch_accepted
grep -Fxq 'reason=database_inventory_mismatch' \
  "$test_root/payload/relationship-pair-failure-result.txt" \
  || fail relationship_pair_mismatch_reason_missing
grep -Fq 'Expected corpus inventory 30;150;786;943;157;943;240;90; observed 30;150;786;943;157;943;240;89.' \
  "$test_root/relationship-pair-failure.stdout" \
  || fail relationship_pair_mismatch_detail_missing
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/relationship-pair-failure-result.txt" \
  || fail relationship_pair_mismatch_cleanup_not_proved

drift_file="$test_root/home/Documents/Ishikawa-v1.3/config/product.yaml"
cp -- "$drift_file" "$test_root/product.yaml.saved"
printf '\ninvalid: drift\n' >>"$drift_file"
run_helper drift
(( helper_status != 0 )) || fail candidate_drift_accepted
grep -Fxq 'reason=staged_candidate_checksum_failed' "$test_root/payload/drift-result.txt" || fail candidate_drift_reason_missing
/usr/bin/cp -- "$test_root/product.yaml.saved" "$drift_file"

run_helper frontier-failure 1
(( helper_status != 0 )) || fail frontier_failure_accepted
grep -Fxq 'reason=frontier_gate_failed' "$test_root/payload/frontier-failure-result.txt" || fail frontier_failure_reason_missing
grep -Fxq 'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  "$test_root/payload/frontier-failure-result.txt" || fail failure_cleanup_not_proved

run_helper model-failure 0 503
(( helper_status != 0 )) || fail model_failure_accepted
grep -Fxq 'reason=gemma_forward_unavailable' "$test_root/payload/model-failure-result.txt" || fail model_failure_reason_missing

[[ "$(stat -Lc '%d:%i' "$test_root/home/Documents/Ishikawa")" == "$active_identity_before" \
    && "$(stat -Lc '%d:%i' "$test_root/home/Documents/Ishikawa-before-v1.2")" == "$rollback_identity_before" ]] \
  || fail v1_2_boundary_changed
(cd -- "$test_root/home/Documents/Ishikawa-v1.3" \
  && sha256sum --check --strict "$test_root/payload/candidate-SHA256SUMS" >/dev/null) \
  || fail candidate_content_changed
if find /tmp -maxdepth 1 -type d -name 'ishikawa-v1.3-qualification.*' -newer "$test_root" -print -quit | grep -q .; then
  fail qualification_workspace_retained
fi

printf '%s\n' \
  'candidate_integrity=pass;credential_tty=pass;credential_prompts_visible=pass;real_candidate_check_config=pass;postgresql_symlink_resolution=pass;target_native_tests=486/486;disposable_database_lifecycle=pass' \
  'target_native_failure_detail=pass;nomic_authenticated_preflight=pass;nomic_failure_root_cause=pass;schema_contract_probe=pass;schema_failure_root_cause=pass;ingestion_validation=pass;ingestion_publication=pass;ingestion_failure_root_cause=pass;api_readiness=pass;frontier_60=pass' \
  'relationship_record_identity=pass;relationship_pair_identity=pass;candidate_drift_rejection=pass;frontier_failure_propagation=pass;model_failure_detail=pass' \
  'cleanup_proof=pass;v1_2_preservation=pass'
printf '\nSCRIPT RESULT\nqualify_candidate_helper_test=pass\n'
