#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Exercise the portable verifier and deployment entrypoint without changing
#   a real host, service, image store, or database.
#
# Mental model:
#   Build one complete private package fixture, replace external host commands
#   with bounded doubles, then run verification, install, schema, lifecycle,
#   cleanup, replay, and refusal paths through the shipped entrypoint.
#
# Inputs or prerequisites:
#   Local shell, Python, jq, tar, checksum tools, and PyYAML. No target, model,
#   credential authority, or protected corpus is contacted.
#
# Outputs or artifact lane:
#   Temporary fixture and mock state exist only beneath /tmp and are removed
#   automatically on success, failure, or interruption.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-deployment-entrypoint.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_deployment_entrypoint_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-deployment-entrypoint.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

carry="$test_root/carry"
home="$test_root/home"
mock_state="$test_root/mock-state"
mkdir -p -- "$carry" "$home/Documents" "$test_root/bin" "$test_root/tmp" \
  "$mock_state" "$test_root/application/ishikawa-v1.3.1/application/payload/application/python/ishikawa" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/config" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/docs" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/scripts" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/systemd" \
  "$test_root/application/ishikawa-v1.3.1/database"
cp -- "$repo_root/deployment/carry/README.md" "$carry/README.md"
cp -- "$repo_root/deployment/carry/SECURITY_REVIEW.md" "$carry/SECURITY_REVIEW.md"
cp -- "$repo_root/deployment/carry/deploy-ishikawa" "$carry/deploy-ishikawa"
cp -- "$repo_root/deployment/carry/verify-deployment" "$carry/verify-deployment"

cat >"$test_root/application/ishikawa-v1.3.1/verify-ishikawa-release" <<'MOCK'
#!/usr/bin/env bash
printf 'ishikawa_release_verification=pass\n'
MOCK
cat >"$test_root/application/ishikawa-v1.3.1/application/install-ishikawa" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --install-root && -n "${2:-}" && ! -e "$2" ]] || exit 1
mkdir -p -- "$(dirname -- "$2")"
cp -a -- "$(dirname -- "${BASH_SOURCE[0]}")/payload/." "$2/"
printf 'ishikawa_install=pass;install_root=%s\n' "$2"
MOCK
cat >"$test_root/application/ishikawa-v1.3.1/database/install-schema" <<'MOCK'
#!/usr/bin/env bash
psql --file="$(dirname -- "${BASH_SOURCE[0]}")/schema.sql" >/dev/null || exit 1
printf 'ishikawa_schema_install=pass;schema_version=5\n'
MOCK
printf 'schema-version-5\n' >"$test_root/application/ishikawa-v1.3.1/database/schema.sql"
printf 'Database schema package.\n' >"$test_root/application/ishikawa-v1.3.1/database/README.md"
(
  cd -- "$test_root/application/ishikawa-v1.3.1/database"
  sha256sum README.md install-schema schema.sql >SHA256SUMS
)
chmod 0755 \
  "$test_root/application/ishikawa-v1.3.1/verify-ishikawa-release" \
  "$test_root/application/ishikawa-v1.3.1/application/install-ishikawa" \
  "$test_root/application/ishikawa-v1.3.1/database/install-schema"

python_package="$test_root/application/ishikawa-v1.3.1/application/payload/application/python/ishikawa"
: >"$python_package/__init__.py"
for module in deployment runtime ingestion_runtime; do
  function_name="validate_${module}"
  [[ "$module" != deployment ]] || function_name=validate_deployment_profile
  [[ "$module" != runtime ]] || function_name=validate_runtime_dependencies
  [[ "$module" != ingestion_runtime ]] || function_name=validate_ingestion_dependencies
  printf 'def %s(value):\n    return value\n' "$function_name" >"$python_package/$module.py"
done

config="$test_root/application/ishikawa-v1.3.1/application/payload/config"
cat >"$config/deployment.yaml" <<'YAML'
schema_version: 1
runtime: {node_network_mode: host}
web: {bind_host: 127.0.0.1, port: 3000, retrieval_base_url: 'http://127.0.0.1:1384'}
retrieval: {bind_host: 127.0.0.1, port: 1384, maximum_concurrent_requests: 8, request_read_timeout_seconds: 30}
postgresql: {bind_host: 127.0.0.1, port: 5432}
YAML
cat >"$config/runtime_dependencies.yaml" <<'YAML'
schema_version: 1
gemma: {chat_endpoint_url: 'http://127.0.0.1:8000/v1/chat/completions', tokenization_endpoint_url: 'http://127.0.0.1:8000/tokenize', health_endpoint_url: 'http://127.0.0.1:8000/health'}
nomic: {embedding_endpoint_url: 'http://127.0.0.1:8001/v1/embeddings', health_endpoint_url: 'http://127.0.0.1:8001/health'}
postgresql: {database_name: rag_catalog}
YAML
cat >"$config/ingestion_dependencies.yaml" <<'YAML'
schema_version: 1
nomic: {embedding_endpoint_url: 'http://127.0.0.1:8001/v1/embeddings', tokenization_endpoint_url: 'http://127.0.0.1:8001/tokenize'}
postgresql: {database_name: rag_catalog}
YAML
cat >"$test_root/application/ishikawa-v1.3.1/application/payload/docs/COMMAND_SHEET.md" <<'DOC'
Web: http://127.0.0.1:3000
Retrieval: http://127.0.0.1:1384/ready
Do not expose ports `3000`, `1384`, or `5432` beyond loopback.
DOC

scripts="$test_root/application/ishikawa-v1.3.1/application/payload/scripts"
cat >"$scripts/ishikawa-retrieval-api" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == --check-config ]] || exit 1
[[ "${MOCK_CONFIG_FAIL:-false}" != true ]]
MOCK
cat >"$scripts/ishikawa-stack" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  start) printf 'ishikawa_stack=start;state=ready;boot_enabled=false\n' ;;
  status) printf 'ishikawa_stack=status;state=stopped;boot_enabled=false\n' ;;
  stop) printf 'ishikawa_stack=stop;state=stopped;boot_enabled=false\n' ;;
  *) exit 2 ;;
esac
MOCK
chmod 0755 "$scripts/"*
for unit in ishikawa-observability-retention.service \
  ishikawa-observability-retention.timer ishikawa-retrieval-api.service; do
  printf '[Unit]\nDescription=Ishikawa\n' \
    >"$test_root/application/ishikawa-v1.3.1/application/payload/systemd/$unit"
done
mkdir -p -- \
  "$test_root/application/ishikawa-v1.3.1/application/payload/corpus/source" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/config/ingestion/pending" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/config/ingestion/completed" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/config/ingestion/rejected" \
  "$test_root/application/ishikawa-v1.3.1/application/payload/state/run"
tar -czf "$carry/ishikawa-v1.3.1.tar.gz" -C "$test_root/application" ishikawa-v1.3.1
(cd -- "$carry" && sha256sum ishikawa-v1.3.1.tar.gz >ishikawa-v1.3.1.tar.gz.sha256)
printf '%064d  Ishikawa/fixture\n' 0 >"$carry/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS"
printf '%s\n' \
  '{"bomFormat":"CycloneDX","metadata":{"component":{"name":"Ishikawa","version":"1.3.1"}}}' \
  >"$carry/application-sbom.cdx.json"
printf '%s\n' \
  '{"application_license":"Apache-2.0","schema":"ishikawa.application-license.v1"}' \
  >"$carry/application-license.json"

mkdir -p -- "$test_root/image/blobs/sha256"
printf '%s\n' \
  '{"architecture":"amd64","os":"linux","config":{"WorkingDir":"/opt/nextjs","Cmd":["next","--help"]},"rootfs":{"type":"layers","diff_ids":["sha256:0000000000000000000000000000000000000000000000000000000000000004"]},"history":[{"created_by":"generic runtime layer"}]}' \
  >"$test_root/image/config.json"
config_hex="$(sha256sum "$test_root/image/config.json" | awk '{print $1}')"
history_sha="$(jq -cS .history "$test_root/image/config.json" | sha256sum | awk '{print $1}')"
printf 'mock compressed layer\n' >"$test_root/image/layer"
layer_hex="$(sha256sum "$test_root/image/layer" | awk '{print $1}')"
mv -- "$test_root/image/config.json" "$test_root/image/blobs/sha256/$config_hex"
mv -- "$test_root/image/layer" "$test_root/image/blobs/sha256/$layer_hex"
printf '[{"Config":"blobs/sha256/%s","RepoTags":["node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"],"Layers":["blobs/sha256/%s"]}]\n' \
  "$config_hex" "$layer_hex" >"$test_root/image/manifest.json"
tar -cf "$carry/node-next-runtime-amd64.tar" -C "$test_root/image" manifest.json blobs
(cd -- "$carry" && sha256sum node-next-runtime-amd64.tar >node-next-runtime-amd64.tar.sha256)
image_sha="$(sha256sum "$carry/node-next-runtime-amd64.tar" | awk '{print $1}')"
application_sha="$(sha256sum "$carry/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
printf '%s\n' \
  '{"bomFormat":"CycloneDX","specVersion":"1.5","metadata":{"component":{"properties":[{"name":"oci:image:config-digest","value":"sha256:'"$config_hex"'"}]}},"components":[{"name":"node","version":"24.22.1","licenses":[{"license":{"id":"MIT"}}]}]}' \
  >"$carry/runtime-sbom.cdx.json"
printf '%s\n' \
  '{"schema":"node-runtime-license-inventory.v2","build_tools":[{"name":"npm","version":"11.21.1","archive_sha256":"dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b","base_bundled_copy_executed":false,"retained_in_runtime":false}],"javascript_packages":[],"operating_system_packages":[],"runtime_tools":[{"name":"node","version":"24.22.1","license":"MIT","license_file":"/usr/local/LICENSE","license_sha256":"'"$(printf '%064d' 1)"'"}]}' \
  >"$carry/runtime-licenses.json"
runtime_sbom_sha="$(sha256sum "$carry/runtime-sbom.cdx.json" | awk '{print $1}')"
runtime_licenses_sha="$(sha256sum "$carry/runtime-licenses.json" | awk '{print $1}')"
security_review_sha="$(sha256sum "$carry/SECURITY_REVIEW.md" | awk '{print $1}')"
python3 -B - "$carry/runtime-image-identity.json" \
  "$carry/deployment-package-receipt.json" "$carry/application-release.json" \
  "$image_sha" "$application_sha" "$config_hex" "$history_sha" \
  "$security_review_sha" <<'PY'
import json
import sys
from pathlib import Path

identity_path, receipt_path, application_release_path, image_sha, application_sha, config_hex, history_sha, security_review_sha = sys.argv[1:]
reference = "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64"
identity = {
    "application_in_image": False,
    "archive_sha256": image_sha,
    "architecture": "amd64",
    "base_bundled_npm_executed": False,
    "base_bundled_yarn_executed": False,
    "build_npm": "11.21.1",
    "build_npm_archive_sha256": "dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b",
    "config_digest": "sha256:" + config_hex,
    "generated_next_in_image": False,
    "history_sha256": history_sha,
    "image_id": "sha256:" + "0" * 64,
    "image_reference": reference,
    "next": "16.4.3",
    "node": "24.22.1",
    "platform": "linux/amd64",
    "react": "19.2.9",
    "react_dom": "19.2.9",
    "runtime_npm": False,
    "runtime_yarn": False,
    "schema": "node-next-runtime-image.v3",
    "tzdata": "2026e-0+deb12u1",
}
receipt = {
    "application_archive_sha256": application_sha,
    "application_release": "Ishikawa v1.3.1",
    "architecture": "amd64",
    "boot_autostart": False,
    "exact_byte_requalification": "pass",
    "human_ui_validation": "accepted",
    "image_archive_sha256": image_sha,
    "image_config_digest": "sha256:" + config_hex,
    "image_history_sha256": history_sha,
    "image_reference": reference,
    "independent_final_review": "pass",
    "platform": "linux/amd64",
    "production_runtime": "pass",
    "release_state": "deployment_ready",
    "schema": "ishikawa.deployment-package-receipt.v1",
    "security_review": "pass",
    "security_review_sha256": security_review_sha,
    "stable_handoff": True,
    "target_inventory": "approved",
}
application_release = {
    "application_archive_sha256": application_sha,
    "coding_standard": "pass",
    "deterministic_archive": True,
    "fresh_install": "pass",
    "human_ui_validation": "accepted",
    "javascript_test_count": 17,
    "native_test_count": 486,
    "production_runtime": "pass",
    "promotion_acceptance_sha256": "1" * 64,
    "promotion_receipt_sha256": "2" * 64,
    "qualification_acceptance_sha256": "3" * 64,
    "qualification_receipt_sha256": "4" * 64,
    "release": "Ishikawa v1.3.1",
    "schema": "ishikawa.application-release.v1",
    "source_build_receipt_sha256": "5" * 64,
    "source_manifest_sha256": "6" * 64,
}
for path, value in ((Path(identity_path), identity), (Path(receipt_path), receipt)):
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
Path(application_release_path).write_text(
    json.dumps(application_release, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
python3 -B - "$carry/runtime-build-receipt.json" "$image_sha" "$config_hex" \
  "$history_sha" "$runtime_sbom_sha" "$runtime_licenses_sha" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "archive_sha256": sys.argv[2],
    "architecture": "amd64",
    "base_bundled_npm_executed": False,
    "base_bundled_yarn_executed": False,
    "build_npm": "11.21.1",
    "build_npm_archive_sha256": "dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b",
    "config_digest": "sha256:" + sys.argv[3],
    "history_sha256": sys.argv[4],
    "image_id": "sha256:" + "0" * 64,
    "image_reference": "node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64",
    "platform": "linux/amd64",
    "runtime_npm": False,
    "runtime_yarn": False,
    "sbom_sha256": sys.argv[5],
    "licenses_sha256": sys.argv[6],
    "schema": "node-next-runtime-build-receipt.v3",
    "tzdata": "2026e-0+deb12u1",
}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
printf 'FROM scratch\n' >"$carry/runtime-Dockerfile"
printf '{"name":"node-next-runtime"}\n' >"$carry/runtime-package.json"
printf '{"lockfileVersion":3}\n' >"$carry/runtime-package-lock.json"
printf 'Generic runtime.\n' >"$carry/RUNTIME_README.md"
printf 'Reviewed security disposition.\n' >"$carry/RUNTIME_SECURITY.md"
printf 'License inventory accompanies this file.\n' >"$carry/RUNTIME_LICENSES.md"

cat >"$carry/inspect-native-prerequisites" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
output=''
postgresql_port=''
retrieval_port=''
web_port=''
gemma_port=''
nomic_port=''
while (( $# > 0 )); do
  case "$1" in
    --output-dir) output="${2:-}"; shift 2 ;;
    --postgresql-port) postgresql_port="${2:-}"; shift 2 ;;
    --retrieval-port) retrieval_port="${2:-}"; shift 2 ;;
    --web-port) web_port="${2:-}"; shift 2 ;;
    --gemma-port) gemma_port="${2:-}"; shift 2 ;;
    --nomic-port) nomic_port="${2:-}"; shift 2 ;;
    --use-sudo-inspection) shift ;;
    *) shift 2 ;;
  esac
done
[[ -n "$output" && ! -e "$output" ]] || exit 1
[[ "${MOCK_INVENTORY_FAIL:-false}" != true ]] || exit 1
mkdir -p -- "$output"
cat >"$output/host-summary.env" <<'DATA'
architecture=amd64
python_yaml_available=true
python_psycopg_available=true
psql_version=16.10
DATA
printf '%s\n' \
  "postgresql_port=$postgresql_port" \
  "retrieval_port=$retrieval_port" \
  "web_port=$web_port" \
  "gemma_port=$gemma_port" \
  "nomic_port=$nomic_port" >>"$output/host-summary.env"
printf 'package\tinstalled_version\tcandidate_version\tarchitecture\tsource\tfilename\tsha256\tsize\tpolicy_sha256\n' >"$output/package-inventory.tsv"
for package in python3 python3-yaml python3-psycopg poppler-utils postgresql-common \
  postgresql-client-16 postgresql-16 postgresql-16-pgvector libpq5; do
  printf '%s\t1\t1\tamd64\tnone\tnone\tnone\tnone\tnone\n' "$package" \
    >>"$output/package-inventory.tsv"
done
printf '[SUMMARY] state=pass;output_dir=%s;mutation=false\n' "$output"
printf '\nSCRIPT RESULT\nishikawa_native_prerequisite_inventory=pass\n'
MOCK
chmod 0755 "$carry/"{deploy-ishikawa,inspect-native-prerequisites,verify-deployment}

write_inventory() {
  python3 -B - "$carry" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
records = []
executable_paths = {"deploy-ishikawa", "inspect-native-prerequisites", "verify-deployment"}
for path in sorted(root.iterdir(), key=lambda item: item.name):
    if not path.is_file() or path.name in {"PACKAGE_MANIFEST.json", "SHA256SUMS"}:
        continue
    records.append({
        "consumer": "fixture",
        "mode": "0755" if path.name in executable_paths else "0644",
        "path": path.name,
        "purpose": "fixture",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size_bytes": path.stat().st_size,
        "type": "file",
    })
record = {
    "control_files": [
        {"consumer": "fixture", "mode": "0644", "path": "PACKAGE_MANIFEST.json", "purpose": "fixture", "type": "file"},
        {"consumer": "fixture", "mode": "0644", "path": "SHA256SUMS", "purpose": "fixture", "type": "file"},
    ],
    "files": records,
    "package_file_count": len(records) + 2,
    "payload_file_count": len(records),
    "payload_total_bytes": sum(item["size_bytes"] for item in records),
    "primary_payloads": ["ishikawa-v1.3.1.tar.gz", "node-next-runtime-amd64.tar"],
    "schema": "ishikawa.deployment-package-manifest.v1",
}
(root / "PACKAGE_MANIFEST.json").write_text(
    json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
}
write_manifest() {
  write_inventory
  (
    cd -- "$carry"
    while IFS= read -r name; do sha256sum -- "$name"; done < <(
      find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
}
write_manifest

cat >"$test_root/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == -v ]]; then exit 0; fi
if [[ "${1:-}" == -u ]]; then shift 2; fi
[[ "${1:-}" != -- ]] || shift
exec "$@"
MOCK
cat >"$test_root/bin/loginctl" <<'MOCK'
#!/usr/bin/env bash
printf 'no\n'
MOCK
cat >"$test_root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${MOCK_STATE:?}"
[[ "${1:-}" != --user ]] || shift
case "${1:-}" in
  is-enabled) printf 'disabled\n'; exit 1 ;;
  is-active)
    [[ -f "$state/postgresql.active" ]] && { printf 'active\n'; exit 0; }
    printf 'inactive\n'; exit 3
    ;;
  start) : >"$state/postgresql.active" ;;
  stop) rm -f -- "$state/postgresql.active" ;;
  cat|show-environment|daemon-reload) exit 0 ;;
  *) exit 91 ;;
esac
MOCK
cat >"$test_root/bin/pg_isready" <<'MOCK'
#!/usr/bin/env bash
[[ -f "${MOCK_STATE:?}/postgresql.active" ]]
MOCK
cat >"$test_root/bin/dropdb" <<'MOCK'
#!/usr/bin/env bash
rm -f -- "${MOCK_STATE:?}/database" "${MOCK_STATE:?}/schema"
MOCK
cat >"$test_root/bin/psql" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${MOCK_STATE:?}"
if [[ "$*" == *'--file='* ]]; then
  [[ "${MOCK_SCHEMA_FAIL:-false}" != true ]] || exit 1
  [[ -f "$state/database" && -f "$state/roles" ]] || exit 1
  : >"$state/schema"
  exit 0
fi
if [[ "$*" == *'shobj_description'* ]]; then
  [[ -f "$state/roles" ]] && printf '3\n' || printf '0\n'
  exit 0
fi
if [[ "$*" == *'DROP ROLE IF EXISTS'* ]]; then
  rm -f -- "$state/roles"
  exit 0
fi
if [[ "$*" == *'pg_terminate_backend'* ]]; then exit 0; fi
input="$(cat)"
if [[ "$input" == *'pg_available_extensions'* ]]; then
  if [[ "${MOCK_DATABASE_DIRTY:-false}" == true ]]; then
    printf '3\n1\n1\n'
  else
    printf '0\n0\n1\n'
  fi
  exit 0
fi
if [[ "$input" == *'CREATE ROLE rag_owner'* ]]; then
  [[ "${MOCK_DATABASE_CREATE_FAIL:-false}" != true ]] || exit 1
  : >"$state/roles"
  : >"$state/database"
  exit 0
fi
exit 0
MOCK
cat >"$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${MOCK_STATE:?}"
case "${1:-}" in
  info) exit 0 ;;
  load)
    : >"$state/image"
    printf 'Loaded image\n'
    ;;
  image)
    case "${2:-}" in
      inspect)
        [[ -f "$state/image" ]] || exit 1
        image_id="$(cat "$state/image")"
        [[ -n "$image_id" ]] || image_id="sha256:$(printf '%064d' 0)"
        case "$*" in
          *'{{.Id}}'*) printf '%s\n' "$image_id" ;;
          *'{{.Architecture}}'*) printf 'amd64\n' ;;
          *) printf '{}\n' ;;
        esac
        ;;
      rm) rm -f -- "$state/image" ;;
      *) exit 92 ;;
    esac
    ;;
  *) exit 93 ;;
esac
MOCK
chmod 0755 "$test_root/bin/"*

export HOME="$home"
export USER='fixture'
export TMPDIR="$test_root/tmp"
export MOCK_STATE="$mock_state"
export PATH="$test_root/bin:$PATH"
deploy="$carry/deploy-ishikawa"

verify_output="$(bash "$deploy" verify 2>&1)" || fail verify_failed
grep -Fq 'ishikawa_deployment_verification=pass;' <<<"$verify_output" \
  || fail verify_marker_missing

mkdir -- "$test_root/protected-source"
inventory_output="$(bash "$deploy" inventory \
  --postgresql-port 55432 --retrieval-port 11384 --web-port 13000 \
  --gemma-port 18000 --nomic-port 18001 \
  --protected-source-root "$test_root/protected-source" \
  --use-sudo-inspection \
  --output-dir "$test_root/tmp/operator-inventory" 2>&1)" \
  || fail inventory_failed
grep -Fxq 'ishikawa_native_prerequisite_inventory=pass' <<<"$inventory_output" \
  || fail inventory_marker_missing
[[ -f "$test_root/tmp/operator-inventory/host-summary.env" \
    && -f "$test_root/tmp/operator-inventory/package-inventory.tsv" ]] \
  || fail inventory_evidence_missing

cp -- "$carry/deployment-package-receipt.json" "$test_root/deployment-package-receipt.json"
python3 -B - "$carry/deployment-package-receipt.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
record = json.loads(path.read_text())
record["security_review"] = "pending_complete_exact_artifact_review"
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
PY
write_manifest
set +e
review_state_output="$(bash "$deploy" verify 2>&1)"
review_state_status="$?"
set -e
(( review_state_status != 0 )) || fail inconsistent_review_state_reported_success
grep -Fxq 'ishikawa_deployment_verification=blocked;reason=identity_record_invalid' \
  <<<"$review_state_output" || fail inconsistent_review_state_reason_missing
mv -- "$test_root/deployment-package-receipt.json" "$carry/deployment-package-receipt.json"
write_manifest

default_install_output="$(bash "$deploy" install 2>&1)" \
  || fail default_install_failed
grep -Fq 'ishikawa_deployment=install;state=pass;' <<<"$default_install_output" \
  || fail default_install_marker_missing
default_inventory_path="$(sed -n 's/.*;inventory=\([^;]*\);boot_enabled=.*/\1/p' \
  <<<"$default_install_output")"
[[ -n "$default_inventory_path" && -f "$default_inventory_path/host-summary.env" ]] \
  || fail default_install_inventory_missing
for expected in postgresql_port=5432 retrieval_port=8384 web_port=3384 \
  gemma_port=8000 nomic_port=8001; do
  grep -Fxq "$expected" "$default_inventory_path/host-summary.env" \
    || fail default_install_inventory_port_invalid
done
python3 -B - "$home/Documents/Ishikawa/config/deployment.yaml" <<'PY' \
  || fail default_configured_ports_invalid
import sys
from pathlib import Path
import yaml
deployment = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert deployment["postgresql"]["port"] == 5432
assert deployment["retrieval"]["port"] == 8384
assert deployment["web"]["port"] == 3384
assert deployment["web"]["retrieval_base_url"] == "http://127.0.0.1:8384"
PY
grep -Fq 'Web: http://127.0.0.1:3384' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail default_operator_web_port_invalid
grep -Fq 'Retrieval: http://127.0.0.1:8384/ready' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail default_operator_retrieval_port_invalid
grep -Fq 'ports `3384`, `8384`, or `5432`' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail default_operator_port_warning_invalid
if grep -ERn '127\.0\.0\.1:(3000|1384)' \
    "$home/Documents/Ishikawa/docs" >/dev/null; then
  fail default_operator_stale_port_found
fi
default_remove_output="$(bash "$deploy" remove --confirm-empty-installation 2>&1)" \
  || fail default_remove_failed
grep -Fq 'ishikawa_deployment=remove;state=application_removed;' \
  <<<"$default_remove_output" || fail default_remove_marker_missing
[[ ! -e "$home/Documents/Ishikawa" && -f "$mock_state/image" ]] \
  || fail default_remove_boundary_invalid

install_output="$(bash "$deploy" install \
  --postgresql-port 55432 --retrieval-port 11384 --web-port 13000 \
  --gemma-port 18000 --nomic-port 18001 2>&1)" || fail install_failed
grep -Fq 'ishikawa_deployment=install;state=pass;' <<<"$install_output" \
  || fail install_marker_missing
override_inventory_path="$(sed -n 's/.*;inventory=\([^;]*\);boot_enabled=.*/\1/p' \
  <<<"$install_output")"
[[ -n "$override_inventory_path" && -f "$override_inventory_path/host-summary.env" ]] \
  || fail override_install_inventory_missing
for expected in postgresql_port=55432 retrieval_port=11384 web_port=13000 \
  gemma_port=18000 nomic_port=18001; do
  grep -Fxq "$expected" "$override_inventory_path/host-summary.env" \
    || fail override_install_inventory_port_invalid
done
[[ -d "$home/Documents/Ishikawa" && -f "$mock_state/image" ]] \
  || fail install_state_missing
for unit in ishikawa-observability-retention.service \
  ishikawa-observability-retention.timer ishikawa-retrieval-api.service; do
  [[ -f "$home/.config/systemd/user/$unit" ]] || fail installed_unit_missing
done
python3 -B - "$home/Documents/Ishikawa/config" <<'PY' || fail configured_ports_invalid
import sys
from pathlib import Path
import yaml
root = Path(sys.argv[1])
deployment = yaml.safe_load((root / "deployment.yaml").read_text())
runtime = yaml.safe_load((root / "runtime_dependencies.yaml").read_text())
ingestion = yaml.safe_load((root / "ingestion_dependencies.yaml").read_text())
assert deployment["postgresql"]["port"] == 55432
assert deployment["retrieval"]["port"] == 11384
assert deployment["web"]["port"] == 13000
assert runtime["gemma"]["chat_endpoint_url"].startswith("http://127.0.0.1:18000/")
assert runtime["nomic"]["embedding_endpoint_url"].startswith("http://127.0.0.1:18001/")
assert ingestion["nomic"]["tokenization_endpoint_url"].startswith("http://127.0.0.1:18001/")
PY
grep -Fq 'Web: http://127.0.0.1:13000' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail override_operator_web_port_invalid
grep -Fq 'Retrieval: http://127.0.0.1:11384/ready' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail override_operator_retrieval_port_invalid
grep -Fq 'ports `13000`, `11384`, or `55432`' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail override_operator_port_warning_invalid

export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD='fixture-ingestion-password'
export ISHIKAWA_POSTGRESQL_PASSWORD='fixture-retrieval-password'
schema_output="$(bash "$deploy" install-schema --postgresql-port 55432 2>&1)" \
  || fail schema_install_failed
grep -Fxq 'ishikawa_deployment_install_schema=pass' <<<"$schema_output" \
  || fail schema_install_marker_missing
[[ -f "$mock_state/database" && -f "$mock_state/roles" && -f "$mock_state/schema" \
    && ! -e "$mock_state/postgresql.active" ]] || fail schema_install_state_invalid
rm -f -- "$mock_state/database" "$mock_state/roles" "$mock_state/schema"
export MOCK_SCHEMA_FAIL=true
set +e
schema_failure_output="$(bash "$deploy" install-schema --postgresql-port 55432 2>&1)"
schema_failure_status="$?"
set -e
unset MOCK_SCHEMA_FAIL
(( schema_failure_status != 0 )) || fail schema_failure_reported_success
grep -Fxq 'reason=schema_install_failed' <<<"$schema_failure_output" \
  || fail schema_failure_reason_missing
[[ ! -e "$mock_state/database" && ! -e "$mock_state/roles" \
    && ! -e "$mock_state/schema" && ! -e "$mock_state/postgresql.active" ]] \
  || fail schema_failure_cleanup_incomplete

for action in start status stop; do
  action_output="$(bash "$deploy" "$action" 2>&1)" || fail "${action}_wrapper_failed"
  grep -Fq "ishikawa_stack=${action};" <<<"$action_output" \
    || fail "${action}_wrapper_marker_missing"
done
set +e
replay_output="$(bash "$deploy" install 2>&1)"
replay_status="$?"
set -e
(( replay_status != 0 )) || fail replay_reported_success
grep -Fxq 'reason=installation_exists' <<<"$replay_output" \
  || fail replay_refusal_missing

remove_output="$(bash "$deploy" remove --confirm-empty-installation 2>&1)" \
  || fail remove_failed
grep -Fq 'ishikawa_deployment=remove;state=application_removed;' <<<"$remove_output" \
  || fail remove_marker_missing
[[ ! -e "$home/Documents/Ishikawa" && -f "$mock_state/image" ]] \
  || fail remove_boundary_invalid

swapped_install_output="$(bash "$deploy" install \
  --retrieval-port 3000 --web-port 1384 2>&1)" \
  || fail swapped_port_install_failed
grep -Fq 'ishikawa_deployment=install;state=pass;' <<<"$swapped_install_output" \
  || fail swapped_port_install_marker_missing
grep -Fq 'Web: http://127.0.0.1:1384' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail swapped_operator_web_port_invalid
grep -Fq 'Retrieval: http://127.0.0.1:3000/ready' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail swapped_operator_retrieval_port_invalid
grep -Fq 'ports `1384`, `3000`, or `5432`' \
  "$home/Documents/Ishikawa/docs/COMMAND_SHEET.md" \
  || fail swapped_operator_port_warning_invalid
swapped_remove_output="$(bash "$deploy" remove --confirm-empty-installation 2>&1)" \
  || fail swapped_remove_failed
grep -Fq 'ishikawa_deployment=remove;state=application_removed;' \
  <<<"$swapped_remove_output" || fail swapped_remove_marker_missing
[[ ! -e "$home/Documents/Ishikawa" && -f "$mock_state/image" ]] \
  || fail swapped_remove_boundary_invalid

rm -f -- "$mock_state/image"
export MOCK_CONFIG_FAIL=true
set +e
failure_output="$(bash "$deploy" install 2>&1)"
failure_status="$?"
set -e
unset MOCK_CONFIG_FAIL
(( failure_status != 0 )) || fail configuration_failure_reported_success
grep -Fxq 'reason=installed_configuration_invalid' <<<"$failure_output" \
  || fail configuration_failure_reason_missing
[[ ! -e "$home/Documents/Ishikawa" && ! -e "$mock_state/image" ]] \
  || fail configuration_failure_cleanup_incomplete

python3 -B - "$carry/deployment-package-receipt.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
record = json.loads(path.read_text())
record["release_state"] = "assembled_pending_security_inventory_and_independent_review"
record["independent_final_review"] = "pending"
record["security_review"] = "pending_complete_exact_artifact_review"
record["stable_handoff"] = False
record["target_inventory"] = "pending"
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
PY
write_manifest
set +e
candidate_output="$(bash "$deploy" install 2>&1)"
candidate_status="$?"
set -e
(( candidate_status != 0 )) || fail candidate_reported_success
grep -Fxq 'reason=carry_not_final' <<<"$candidate_output" \
  || fail candidate_refusal_missing
[[ ! -e "$home/Documents/Ishikawa" && ! -e "$mock_state/image" ]] \
  || fail candidate_preflight_mutated

printf '%s\n' \
  'verify=pass;review_state_correlation=pass;inventory_command=pass;inventory_preflight=pass;install=pass;configuration=pass;schema=pass' \
  'start_status_stop=pass;replay_refusal=pass;empty_removal=pass' \
  'schema_failure_cleanup=pass;failure_cleanup=pass;candidate_refusal_before_mutation=pass'
printf '\nSCRIPT RESULT\nishikawa_deployment_entrypoint_test=pass\n'
