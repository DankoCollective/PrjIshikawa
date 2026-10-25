#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Capture one transportable linux/amd64 Docker image bundle for the first
#   application slice. The bundle contains the already accepted Node/Next.js
#   runtime plus exact Python and PostgreSQL/pgvector runtime candidates.
#
# Scope:
#   This script runs only against the Docker daemon on the workstation where
#   the operator invokes it. It does not use SSH, SCP, an API credential, or a
#   remote system. It does not build an image, start a container, stop a
#   container, or alter the accepted Node/Next.js image.
#
# Network and storage effects:
#   It pulls two public linux/amd64 images, leaves them in the local Docker
#   cache, and writes one Docker-save tar plus manifests and checksums under
#   the ignored local artifact tree. The accepted Node/Next.js image must
#   already exist locally and is never pulled or rebuilt by this script.
#
# Run from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/04_capture_application_runtime_images.sh

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --artifact-root PATH   Absolute output parent for captured artifacts.' \
    '  --report-root PATH     Absolute output directory for reports.' \
    '  --validate-only        Validate this capture definition without Docker or network access.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"

# The Node image is the previously built and accepted reusable runtime. The
# other two references use exact language/extension releases and explicit
# distribution or PostgreSQL-major variants. Registry digests are captured
# after pull and become the immutable identities used by later installation.
readonly NODE_IMAGE='node-24-slim-nextjs-16-4-1:amd64'
readonly EXPECTED_NODE_PLATFORM_IMAGE_ID='sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6'
readonly PYTHON_IMAGE='python:3.12.15-slim-trixie'
readonly PGVECTOR_IMAGE='pgvector/pgvector:0.8.7-pg17-bookworm'
readonly TARGET_PLATFORM='linux/amd64'
readonly EXPECTED_PYTHON_VERSION='3.12.15'
readonly EXPECTED_POSTGRES_MAJOR='17'
readonly BUNDLE_NAME='application-runtime-images-linux-amd64.tar'
readonly MANIFEST_NAME='runtime-image-manifest.txt'
readonly CHECKSUM_NAME='SHA256SUMS'
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/application-runtime-images"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/application-runtime-images"

artifact_root="$DEFAULT_ARTIFACT_ROOT"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$artifact_root" == /* ]] \
  || { printf 'BLOCKED: --artifact-root must be absolute.\n' >&2; exit 2; }
[[ "$report_root" == /* ]] \
  || { printf 'BLOCKED: --report-root must be absolute.\n' >&2; exit 2; }
[[ ! -L "$artifact_root" ]] \
  || { printf 'BLOCKED: --artifact-root cannot be a symbolic link.\n' >&2; exit 2; }
[[ ! -L "$report_root" ]] \
  || { printf 'BLOCKED: --report-root cannot be a symbolic link.\n' >&2; exit 2; }

for required in awk bash date df grep id mkdir mktemp mv python3 rm sha256sum stat sudo tar tee tr wc; do
  command -v "$required" >/dev/null 2>&1 \
    || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'application_runtime_image_capture_definition=pass' \
    'docker_contact=false' \
    'network_access=false' \
    'remote_contact=false' \
    "target_platform=$TARGET_PLATFORM" \
    "node_image=$NODE_IMAGE" \
    "python_image=$PYTHON_IMAGE" \
    "pgvector_image=$PGVECTOR_IMAGE"
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/capture_application_runtime_images_${timestamp}_XXXXXX.txt")"
staging_root="$(mktemp -d "$artifact_root/.application-runtime-images-${timestamp}.XXXXXX")"
final_root="$artifact_root/application-runtime-images-linux-amd64-$timestamp"
promoted=false

exec > >(tee "$report_path") 2>&1

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if [[ "$promoted" != true && "$staging_root" == "$artifact_root"/.application-runtime-images-* && -d "$staging_root" ]]; then
    rm -rf -- "$staging_root"
    printf 'cleanup_incomplete_staging=removed\n'
  else
    printf 'cleanup_incomplete_staging=not_required\n'
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit() {
  printf '%s\n' "$1"
}

block() {
  emit "application_runtime_image_capture=blocked;reason=$1"
  exit 1
}

emit 'schema=application-runtime-image-capture/v1'
emit "started_utc=$timestamp"
emit 'execution_scope=local_docker_daemon_only'
emit 'authorized_mutations=reuse_or_pull_two_public_images_leave_pulled_layers_write_ignored_local_artifacts'
emit 'non_actions=no_ssh_no_scp_no_remote_contact_no_image_build_no_container_run_no_container_stop_no_node_image_change_no_secret_read'
emit "target_platform=$TARGET_PLATFORM"
emit "node_image=$NODE_IMAGE"
emit "python_image=$PYTHON_IMAGE"
emit "pgvector_image=$PGVECTOR_IMAGE"

docker_cmd=()
if docker info >/dev/null 2>&1; then
  docker_cmd=(docker)
  emit 'docker_authorization=direct'
elif sudo -n docker info >/dev/null 2>&1; then
  docker_cmd=(sudo -n docker)
  emit 'docker_authorization=cached_or_passwordless_sudo'
else
  [[ -r /dev/tty && -w /dev/tty ]] \
    || block attended_sudo_terminal_unavailable
  emit 'milestone=local_docker_sudo;state=waiting_for_operator_if_prompted'
  sudo -p 'Local Docker sudo password: ' -v </dev/tty >/dev/tty 2>/dev/tty \
    || block local_sudo_authentication_failed
  sudo -n docker info >/dev/null 2>&1 \
    || block docker_daemon_unavailable_after_sudo
  docker_cmd=(sudo -n docker)
  emit 'docker_authorization=attended_sudo'
fi
emit 'milestone=local_docker_sudo;state=pass'

available_kib="$(df -Pk "$artifact_root" | awk 'NR == 2 {print $4}')"
[[ "$available_kib" =~ ^[0-9]+$ ]] || block artifact_filesystem_capacity_unknown
emit "artifact_filesystem_available_kib=$available_kib"
(( available_kib >= 2097152 )) || block less_than_2_gib_available_for_capture

if ! "${docker_cmd[@]}" image inspect --platform "$TARGET_PLATFORM" "$NODE_IMAGE" >/dev/null 2>&1; then
  block accepted_node_image_missing_load_existing_amd64_bundle_first
fi

ensure_image() {
  local reference="$1" label="$2"
  if "${docker_cmd[@]}" image inspect --platform "$TARGET_PLATFORM" "$reference" >/dev/null 2>&1; then
    emit "milestone=acquire_$label;state=pass;source=existing_local_linux_amd64_image;registry_contact=false"
    return 0
  fi
  emit "milestone=pull_$label;state=running"
  if ! "${docker_cmd[@]}" pull --platform "$TARGET_PLATFORM" "$reference"; then
    block "${label}_image_pull_failed"
  fi
  emit "milestone=acquire_$label;state=pass;source=public_registry_pull;registry_contact=true"
}

ensure_image "$PYTHON_IMAGE" python
ensure_image "$PGVECTOR_IMAGE" pgvector

image_environment_value() {
  local reference="$1" key="$2"
  "${docker_cmd[@]}" image inspect --platform "$TARGET_PLATFORM" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' "$reference" \
    | awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}'
}

image_repository_digest() {
  local reference="$1" repository="$2" digest=''
  while IFS= read -r candidate; do
    case "$candidate" in
      "$repository"@sha256:*) digest="$candidate"; break ;;
    esac
  done < <("${docker_cmd[@]}" image inspect --platform "$TARGET_PLATFORM" \
    --format '{{range .RepoDigests}}{{println .}}{{end}}' "$reference")
  printf '%s' "$digest"
}

inspect_image() {
  local reference="$1" label="$2" require_digest="$3"
  local details architecture os image_id size_bytes repository repo_digest
  details="$("${docker_cmd[@]}" image inspect --platform "$TARGET_PLATFORM" \
    --format '{{.Architecture}}|{{.Os}}|{{.Id}}|{{.Size}}' "$reference")" \
    || block "${label}_image_inspect_failed"
  IFS='|' read -r architecture os image_id size_bytes <<<"$details"
  [[ "$architecture" == amd64 && "$os" == linux ]] \
    || block "${label}_image_platform_is_not_linux_amd64"
  [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || block "${label}_image_id_invalid"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] \
    || block "${label}_image_size_invalid"

  repository="${reference%:*}"
  repo_digest="$(image_repository_digest "$reference" "$repository")"
  if [[ "$require_digest" == true && ! "$repo_digest" =~ ^.+@sha256:[0-9a-f]{64}$ ]]; then
    block "${label}_registry_digest_missing"
  fi
  [[ -n "$repo_digest" ]] || repo_digest='not_available_for_local_custom_image'

  printf -v "${label}_architecture" '%s' "$architecture"
  printf -v "${label}_os" '%s' "$os"
  printf -v "${label}_image_id" '%s' "$image_id"
  printf -v "${label}_size_bytes" '%s' "$size_bytes"
  printf -v "${label}_repo_digest" '%s' "$repo_digest"
  emit "image_validation=$label;state=pass;architecture=$architecture;os=$os;image_id=$image_id;size_bytes=$size_bytes;repo_digest=$repo_digest"
}

inspect_image "$NODE_IMAGE" node false
inspect_image "$PYTHON_IMAGE" python true
inspect_image "$PGVECTOR_IMAGE" pgvector true
[[ "$node_image_id" == "$EXPECTED_NODE_PLATFORM_IMAGE_ID" ]] \
  || block node_platform_image_id_does_not_match_accepted_emceedanko_image
emit 'node_platform_image_identity=matches_accepted_emceedanko_image'

python_version="$(image_environment_value "$PYTHON_IMAGE" PYTHON_VERSION)"
postgres_major="$(image_environment_value "$PGVECTOR_IMAGE" PG_MAJOR)"
postgres_version="$(image_environment_value "$PGVECTOR_IMAGE" PG_VERSION)"
[[ "$python_version" == "$EXPECTED_PYTHON_VERSION" ]] \
  || block python_environment_version_mismatch
[[ "$postgres_major" == "$EXPECTED_POSTGRES_MAJOR" ]] \
  || block postgres_environment_major_mismatch
[[ "$postgres_version" == "$EXPECTED_POSTGRES_MAJOR".* ]] \
  || block postgres_environment_version_mismatch
emit "python_runtime_version=$python_version"
emit "postgres_runtime_major=$postgres_major;postgres_runtime_version=$postgres_version"

bundle_path="$staging_root/$BUNDLE_NAME"
manifest_path="$staging_root/$MANIFEST_NAME"
checksum_path="$staging_root/$CHECKSUM_NAME"

emit 'milestone=docker_save;state=running'
if ! "${docker_cmd[@]}" image save --platform "$TARGET_PLATFORM" \
    "$NODE_IMAGE" "$PYTHON_IMAGE" "$PGVECTOR_IMAGE" >"$bundle_path"; then
  block docker_save_failed
fi
[[ -s "$bundle_path" ]] || block docker_save_bundle_empty
emit 'milestone=docker_save;state=pass'

archive_metadata_path="$staging_root/archive-image-identities.txt"
python3 - "$bundle_path" \
  "node=$NODE_IMAGE" "python=$PYTHON_IMAGE" "pgvector=$PGVECTOR_IMAGE" \
  >"$archive_metadata_path" <<'PY'
import hashlib
import json
import sys
import tarfile

bundle, *labelled_tags = sys.argv[1:]
required = dict(item.split("=", 1) for item in labelled_tags)
with tarfile.open(bundle, mode="r:*") as archive:
    members = {member.name.lstrip("./"): member for member in archive.getmembers()}
    manifest_member = members.get("manifest.json")
    if manifest_member is None or not manifest_member.isfile():
        raise SystemExit("Docker archive is missing manifest.json")
    stream = archive.extractfile(manifest_member)
    if stream is None:
        raise SystemExit("Docker archive manifest.json is unreadable")
    manifest = json.load(stream)

    entries_by_tag = {
        tag: entry
        for entry in manifest
        for tag in entry.get("RepoTags") or []
    }
    missing = sorted(set(required.values()) - set(entries_by_tag))
    if missing:
        raise SystemExit("Docker archive is missing required tags: " + ", ".join(missing))

    for label, tag in required.items():
        config_name = entries_by_tag[tag].get("Config", "").lstrip("./")
        config_member = members.get(config_name)
        if not config_name or config_member is None or not config_member.isfile():
            raise SystemExit(f"Docker archive config is missing for {tag}")
        config_stream = archive.extractfile(config_member)
        if config_stream is None:
            raise SystemExit(f"Docker archive config is unreadable for {tag}")
        config_digest = "sha256:" + hashlib.sha256(config_stream.read()).hexdigest()
        print(f"{label}_archive_config_digest={config_digest}")

print(f"docker_archive_manifest=pass;required_tag_count={len(required)}")
PY

cat "$archive_metadata_path"
node_archive_config_digest="$(awk -F= '$1 == "node_archive_config_digest" {print $2; exit}' "$archive_metadata_path")"
python_archive_config_digest="$(awk -F= '$1 == "python_archive_config_digest" {print $2; exit}' "$archive_metadata_path")"
pgvector_archive_config_digest="$(awk -F= '$1 == "pgvector_archive_config_digest" {print $2; exit}' "$archive_metadata_path")"
for archive_digest in "$node_archive_config_digest" "$python_archive_config_digest" "$pgvector_archive_config_digest"; do
  [[ "$archive_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || block runtime_archive_config_digest_invalid
done
rm -f -- "$archive_metadata_path"

bundle_bytes="$(stat -c '%s' "$bundle_path")"
bundle_sha256="$(sha256sum "$bundle_path" | awk '{print $1}')"
docker_client_version="$("${docker_cmd[@]}" version --format '{{.Client.Version}}')"
docker_server_version="$("${docker_cmd[@]}" version --format '{{.Server.Version}}')"

cat >"$manifest_path" <<EOF
schema=application-runtime-images/v1
created_utc=$timestamp
target_platform=$TARGET_PLATFORM
docker_client_version=$docker_client_version
docker_server_version=$docker_server_version
node_reference=$NODE_IMAGE
node_architecture=$node_architecture
node_os=$node_os
node_image_id=$node_image_id
node_repository_digest=$node_repo_digest
node_archive_config_digest=$node_archive_config_digest
node_size_bytes=$node_size_bytes
python_reference=$PYTHON_IMAGE
python_version=$python_version
python_architecture=$python_architecture
python_os=$python_os
python_image_id=$python_image_id
python_repository_digest=$python_repo_digest
python_archive_config_digest=$python_archive_config_digest
python_size_bytes=$python_size_bytes
pgvector_reference=$PGVECTOR_IMAGE
pgvector_extension_version=0.8.7
postgres_major=$postgres_major
postgres_version=$postgres_version
pgvector_architecture=$pgvector_architecture
pgvector_os=$pgvector_os
pgvector_image_id=$pgvector_image_id
pgvector_repository_digest=$pgvector_repo_digest
pgvector_archive_config_digest=$pgvector_archive_config_digest
pgvector_size_bytes=$pgvector_size_bytes
bundle_file=$BUNDLE_NAME
bundle_size_bytes=$bundle_bytes
bundle_sha256=$bundle_sha256
application_source_included=false
corpus_included=false
database_state_included=false
secrets_included=false
EOF

(
  cd -- "$staging_root"
  sha256sum "$BUNDLE_NAME" "$MANIFEST_NAME" >"$CHECKSUM_NAME"
  sha256sum --check --strict "$CHECKSUM_NAME"
)

[[ ! -e "$final_root" ]] || block final_artifact_path_already_exists
mv -- "$staging_root" "$final_root"
promoted=true

emit "bundle_sha256=$bundle_sha256;bundle_size_bytes=$bundle_bytes"
emit "application_runtime_image_capture=pass;artifact_root=$final_root;report=$report_path"
emit 'next_gate=operator_review_then_transfer_and_load_test_on_emceedanko'
