#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Capture a checksum-bound offline native PostgreSQL, pgvector, and Psycopg 3
#   Debian-package closure using exact package candidates accepted by the
#   read-only target inventory.
#
# Default execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh
#
# The operator may be prompted for the SSH key passphrase. The remote helper
# uses existing apt metadata only, streams its metadata bundle back, and
# removes its own temporary state. Package downloads occur only on this local
# workstation. No package is installed and no database or service is changed.

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target VALUE              SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME    Exact target short hostname.' \
    '  --expected-os-version VER   Expected Ubuntu major or major.minor version.' \
    '  --identity-file PATH        Optional explicit SSH private key.' \
    '  --inventory-report PATH     Accepted local Script 05 report.' \
    '  --artifact-root PATH        Absolute local artifact parent.' \
    '  --report-root PATH          Absolute local report directory.' \
    '  --resume-latest             Resume the newest verified incomplete capture.' \
    '  --resume-check-only         Validate resumable metadata without downloading.' \
    '  --validate-only             Validate source without target/network contact.' \
    '  --plan-only                 Validate accepted roots without target/network contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/collect-native-postgresql-package-metadata"
readonly DEFAULT_INVENTORY_ROOT="$REPO_ROOT/local/reports/native-postgresql-package-inventory"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/native-postgresql-packages"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-package-capture"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
inventory_report="${NATIVE_POSTGRESQL_INVENTORY_REPORT:-}"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false
plan_only=false
resume_latest=false
resume_check_only=false

while (( $# > 0 )); do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --inventory-report) inventory_report="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --resume-latest) resume_latest=true; shift ;;
    --resume-check-only) resume_latest=true; resume_check_only=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --plan-only) plan_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$resume_latest" == true && ( "$validate_only" == true || "$plan_only" == true ) ]]; then
  printf 'BLOCKED: --resume-latest cannot be combined with a validation-only option.\n' >&2
  exit 2
fi

for path in "$artifact_root" "$report_root"; do
  [[ "$path" == /* ]] \
    || { printf 'BLOCKED: artifact and report roots must be absolute.\n' >&2; exit 2; }
  [[ ! -L "$path" ]] \
    || { printf 'BLOCKED: artifact and report roots cannot be symbolic links.\n' >&2; exit 2; }
done
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] \
  || { printf 'BLOCKED: neutral package metadata helper is missing or unsafe.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
  || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}(\.[0-9]{2})?$ ]] \
  || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash basename cp curl date dpkg-deb find grep mkdir mktemp python3 rm sed sha256sum sort ssh tail tar tee timeout tr wc xargs; do
  command -v "$required" >/dev/null 2>&1 \
    || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: environment or control jargon found in neutral target helper.\n' >&2
  exit 2
fi

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_package_capture_source=pass' \
    'target_contact=false' \
    'network_download=false' \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes"
  exit 0
fi

latest_accepted_inventory() {
  local candidate selected=""
  while IFS= read -r candidate; do
    if grep -Fqx 'native_postgresql_package_inventory=pass' "$candidate" \
        && grep -Fqx 'capture_readiness=ready_for_package_root_review' "$candidate" \
        && grep -Fqx 'remote_output_contract=pass' "$candidate"; then
      selected="$candidate"
    fi
  done < <(find "$DEFAULT_INVENTORY_ROOT" -maxdepth 1 -type f \
    -name 'native_postgresql_package_inventory_*.txt' -print | sort)
  [[ -n "$selected" ]] && printf '%s\n' "$selected"
}

if [[ -z "$inventory_report" ]]; then
  inventory_report="$(latest_accepted_inventory || true)"
fi
[[ -n "$inventory_report" && -f "$inventory_report" && ! -L "$inventory_report" && -r "$inventory_report" ]] \
  || { printf 'BLOCKED: accepted Script 05 inventory report not found.\n' >&2; exit 2; }

grep -Fqx 'native_postgresql_package_inventory=pass' "$inventory_report" \
  && grep -Fqx 'capture_readiness=ready_for_package_root_review' "$inventory_report" \
  && grep -Fqx 'remote_output_contract=pass' "$inventory_report" \
  || { printf 'BLOCKED: inventory report is not an accepted ready result.\n' >&2; exit 2; }
grep -Fqx 'dpkg_architecture=amd64' "$inventory_report" \
  || { printf 'BLOCKED: inventory report is not for amd64.\n' >&2; exit 2; }
grep -Fqx "os_version=$expected_os_version" "$inventory_report" \
  || { printf 'BLOCKED: inventory OS version does not match this capture.\n' >&2; exit 2; }

report_field() {
  local label="$1" field="$2"
  awk -v prefix="package_${label}=" -v wanted="$field" '
    index($0, prefix) == 1 {
      count = split($0, values, ";")
      for (index_value = 1; index_value <= count; index_value++) {
        split(values[index_value], pair, "=")
        if (pair[1] == wanted) {
          print substr(values[index_value], length(pair[1]) + 2)
          exit
        }
      }
    }
  ' "$inventory_report"
}

default_major="$(awk -F= '$1 == "default_postgresql_major" {print $2; exit}' "$inventory_report")"
[[ "$default_major" =~ ^[0-9]+$ ]] \
  || { printf 'BLOCKED: inventory did not resolve a PostgreSQL major.\n' >&2; exit 2; }

root_labels=(
  "postgresql_${default_major}"
  "postgresql_client_${default_major}"
  "postgresql_pgvector_${default_major}"
  python3_psycopg
)
root_specs=()
for label in "${root_labels[@]}"; do
  package="$(report_field "$label" name)"
  version="$(report_field "$label" candidate_version)"
  sha256="$(report_field "$label" sha256)"
  [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ \
      && "$version" =~ ^[A-Za-z0-9.+:~_-]+$ \
      && "$version" != absent \
      && "$sha256" =~ ^[0-9a-f]{64}$ ]] \
    || { printf 'BLOCKED: incomplete accepted root metadata for %s.\n' "$label" >&2; exit 2; }
  root_specs+=("${package}=${version}")
done

inventory_sha256="$(sha256sum "$inventory_report" | awk '{print $1}')"
inventory_basename="$(basename "$inventory_report")"
if [[ "$plan_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_package_capture_plan=pass' \
    'target_contact=false' \
    'network_download=false' \
    "inventory_report=$inventory_basename" \
    "inventory_sha256=$inventory_sha256" \
    "selected_roots=$(IFS=,; printf '%s' "${root_specs[*]}")"
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "$resume_latest" == true ]]; then
  artifact_dir="$(find "$artifact_root" -mindepth 1 -maxdepth 1 -type d \
    -name "native-postgresql-ubuntu${expected_os_version}-amd64-*" -print | sort | tail -n 1)"
  [[ -n "$artifact_dir" && -d "$artifact_dir" && ! -L "$artifact_dir" ]] \
    || { printf 'BLOCKED: no resumable capture directory was found.\n' >&2; exit 2; }
  label="$(basename "$artifact_dir")"
else
  label="native-postgresql-ubuntu${expected_os_version}-amd64-${timestamp}"
  artifact_dir="$artifact_root/$label"
fi
bundle_path="$artifact_root/${label}.tar.gz"
bundle_sidecar="$bundle_path.sha256"
report_path="$(mktemp "$report_root/native_postgresql_package_capture_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-package-capture.XXXXXX)"

if [[ "$resume_latest" == true ]]; then
  [[ ! -e "$bundle_path" && ! -e "$bundle_sidecar" ]] \
    || { printf 'BLOCKED: latest capture already has a bundle or sidecar.\n' >&2; exit 2; }
else
  [[ ! -e "$artifact_dir" && ! -e "$bundle_path" && ! -e "$bundle_sidecar" ]] \
    || { printf 'BLOCKED: capture target already exists.\n' >&2; exit 2; }
fi

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/native-postgresql-package-capture.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

emit 'purpose=capture_native_postgresql_pgvector_and_psycopg_offline_package_closure'
emit "started_utc=$timestamp"
emit "helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "inventory_report=$inventory_basename;inventory_sha256=$inventory_sha256"
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;expected_architecture=amd64"
emit "selected_roots=$(IFS=,; printf '%s' "${root_specs[*]}")"
emit "resume_latest=$resume_latest;artifact_label=$label"
emit 'authorized_actions=read_target_apt_metadata_stream_temporary_metadata_download_exact_packages_locally_capture_public_advisories_write_local_ignored_artifacts'
emit 'non_actions=no_apt_update_no_remote_download_no_install_no_database_initialization_no_service_or_configuration_change_no_secret_or_content_read'

metadata_archive="$work_root/target-metadata.tar.gz"
mkdir -p -- "$artifact_dir/target-metadata" "$artifact_dir/packages" \
  "$artifact_dir/advisories" "$artifact_dir/licenses" "$artifact_dir/package-filelists"

if [[ "$resume_latest" == true ]]; then
  emit 'milestone=target_metadata;state=resume_verification'
  metadata_dir="$artifact_dir/target-metadata"
  for required_metadata in SHA256SUMS capture_summary.env host_summary.env \
      package_uris.tsv resolved_packages.tsv root_package_records.tsv; do
    [[ -f "$metadata_dir/$required_metadata" && ! -L "$metadata_dir/$required_metadata" ]] \
      || { emit "native_postgresql_package_capture=blocked;reason=resume_metadata_missing;file=$required_metadata"; exit 1; }
  done
  if ! (cd "$metadata_dir" && sha256sum -c SHA256SUMS) \
      >"$work_root/resume-metadata-check.txt" 2>&1; then
    emit 'native_postgresql_package_capture=blocked;reason=resume_metadata_checksum_failure'
    exit 1
  fi
  grep -Fqx 'complete_closure=true' "$metadata_dir/capture_summary.env" \
    || { emit 'native_postgresql_package_capture=blocked;reason=resume_closure_not_complete'; exit 1; }
  grep -Fqx 'os_id=ubuntu' "$metadata_dir/host_summary.env" \
    && grep -Fqx 'dpkg_architecture=amd64' "$metadata_dir/host_summary.env" \
    || { emit 'native_postgresql_package_capture=blocked;reason=resume_platform_mismatch'; exit 1; }
  resolved_count="$(( $(wc -l <"$metadata_dir/resolved_packages.tsv") - 1 ))"
  uri_count="$(( $(wc -l <"$metadata_dir/package_uris.tsv") - 1 ))"
  [[ "$resolved_count" -gt 0 && "$resolved_count" -eq "$uri_count" ]] \
    || { emit 'native_postgresql_package_capture=blocked;reason=resume_package_count_mismatch'; exit 1; }
  grep -Fqx "resolved_package_count=$resolved_count" "$metadata_dir/capture_summary.env" \
    && grep -Fqx "package_uri_count=$uri_count" "$metadata_dir/capture_summary.env" \
    || { emit 'native_postgresql_package_capture=blocked;reason=resume_summary_count_mismatch'; exit 1; }
  for spec in "${root_specs[@]}"; do
    package="${spec%%=*}"
    version="${spec#*=}"
    awk -F '\t' -v package="$package" -v version="$version" '
      NR > 1 && $1 == package && $3 == version && ($4 == "amd64" || $4 == "all") {count++}
      END {exit(count == 1 ? 0 : 1)}
    ' "$metadata_dir/root_package_records.tsv" \
      || { emit "native_postgresql_package_capture=blocked;reason=resume_root_mismatch;package=$package"; exit 1; }
  done
  tar -C "$metadata_dir" -czf "$metadata_archive" .
  emit "target_metadata_reused=true;resolved_package_count=$resolved_count;package_uri_count=$uri_count;target_contact=false"
else
  ssh_stderr="$work_root/ssh.stderr"
  ssh_args=(
    -o StrictHostKeyChecking=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=5
  )
  if [[ -n "$identity_file" ]]; then
    ssh_args+=( -i "$identity_file" -o IdentitiesOnly=yes )
  fi

  emit 'milestone=target_metadata;state=start'
  set +e
  timeout --foreground 600 ssh "${ssh_args[@]}" "$target" \
    -- /bin/bash -s -- "$expected_hostname" "$expected_os_version" amd64 "${root_specs[@]}" \
    <"$TARGET_HELPER" >"$metadata_archive" 2>"$ssh_stderr"
  remote_code=$?
  set -e
  emit "target_metadata_exit_code=$remote_code;raw_stderr_retained=false"
  if (( remote_code != 0 )); then
    classification=target_metadata_collection_blocked
    if grep -Eiq 'package_candidate_changed' "$ssh_stderr"; then
      classification=accepted_candidate_changed
    elif grep -Eiq 'unresolved dependency metadata|apt URI output missing' "$ssh_stderr"; then
      classification=dependency_closure_incomplete
    elif grep -Eiq 'permission denied.*publickey' "$ssh_stderr"; then
      classification=public_key_authentication_rejected
    elif grep -Eiq 'host key verification failed|remote host identification has changed' "$ssh_stderr"; then
      classification=host_key_rejected
    elif grep -Eiq 'connection timed out|operation timed out' "$ssh_stderr" || (( remote_code == 124 )); then
      classification=timeout
    fi
    emit "native_postgresql_package_capture=blocked;reason=$classification;local_report=$report_path"
    exit 1
  fi

  tar -tzf "$metadata_archive" >"$work_root/archive-members.txt"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$work_root/archive-members.txt"; then
    emit "native_postgresql_package_capture=blocked;reason=unsafe_metadata_archive_path;local_report=$report_path"
    exit 1
  fi
  tar -xzf "$metadata_archive" -C "$artifact_dir/target-metadata"
  if ! (cd "$artifact_dir/target-metadata" && sha256sum -c SHA256SUMS) \
      >"$work_root/metadata-check.txt" 2>&1; then
    emit 'native_postgresql_package_capture=blocked;reason=target_metadata_checksum_failure'
    exit 1
  fi
fi
emit 'milestone=target_metadata;state=pass'

cp -- "$metadata_archive" "$artifact_dir/target-metadata.tar.gz"

record_unexpected_failure() {
  local status="$1" line="$2"
  trap - ERR
  set +e
  printf 'native_postgresql_package_capture=blocked;reason=unexpected_local_failure;exit_code=%s;line=%s;local_report=%s\n' \
    "$status" "$line" "$report_path" | tee -a "$report_path" >&2
  exit "$status"
}
trap 'status=$?; record_unexpected_failure "$status" "$LINENO"' ERR
{
  printf 'schema=native-postgresql-capture-provenance/v1\n'
  printf 'inventory_report=%s\n' "$inventory_basename"
  printf 'inventory_sha256=%s\n' "$inventory_sha256"
  printf 'metadata_helper_sha256=%s\n' "$helper_sha256"
  printf 'selected_roots=%s\n' "$(IFS=,; printf '%s' "${root_specs[*]}")"
  printf 'target_os=ubuntu%s\n' "$expected_os_version"
  printf 'target_architecture=amd64\n'
  printf 'package_install=false\n'
} >"$artifact_dir/capture_provenance.env"

download_manifest="$artifact_dir/capture-package-uris.tsv"
python3 - \
  "$artifact_dir/target-metadata/apt_simulated_install.txt" \
  "$artifact_dir/target-metadata/package_uris.tsv" \
  "$download_manifest" <<'PY'
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

simulation_path = Path(sys.argv[1])
full_manifest_path = Path(sys.argv[2])
download_manifest_path = Path(sys.argv[3])

install_re = re.compile(r"^Inst\s+(\S+)\s+\((\S+)")
required: list[tuple[str, str]] = []
for raw_line in simulation_path.read_text(encoding="utf-8", errors="strict").splitlines():
    match = install_re.match(raw_line)
    if match:
        package, version = match.groups()
        package = package.split(":", 1)[0]
        required.append((package, version))

if not required:
    raise SystemExit("apt simulation contains no packages requiring capture")
if len(required) != len(set(required)):
    raise SystemExit("apt simulation contains duplicate install coordinates")

with full_manifest_path.open(encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    columns = reader.fieldnames
    rows = list(reader)
if not columns:
    raise SystemExit("full package URI manifest has no header")

by_coordinate = {(row["package"], row["version"]): row for row in rows}
selected = []
for coordinate in required:
    row = by_coordinate.get(coordinate)
    if row is None:
        raise SystemExit(
            f"required apt coordinate missing from verified metadata: {coordinate[0]}={coordinate[1]}"
        )
    selected.append(row)

with download_manifest_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(selected)

print(f"target_required_package_count={len(selected)}")
print(f"target_required_download_bytes={sum(int(row['size']) for row in selected)}")
PY

download_package_count="$(( $(wc -l <"$download_manifest") - 1 ))"
download_bytes="$(awk -F '\t' 'NR > 1 {sum += $6} END {printf "%.0f", sum}' "$download_manifest")"
emit "resolved_dependency_count=$(($(wc -l <"$artifact_dir/target-metadata/resolved_packages.tsv") - 1));download_package_count=$download_package_count;download_bytes=$download_bytes"

if [[ "$resume_check_only" == true ]]; then
  emit "native_postgresql_package_capture_resume_check=pass;artifact_directory=$artifact_dir;target_contact=false;package_download=false"
  exit 0
fi

emit 'milestone=local_package_download;state=start'
python3 - "$download_manifest" "$artifact_dir/packages" <<'PY'
from __future__ import annotations

import csv
import hashlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

records_path = Path(sys.argv[1])
package_dir = Path(sys.argv[2])
rows = list(csv.DictReader(records_path.open(encoding="utf-8"), delimiter="\t"))
if not rows:
    raise SystemExit("package URI manifest is empty")

filename_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+%:~_-]*\.deb$")
for row in rows:
    uri = row["uri"]
    filename = row["local_filename"]
    expected_sha = row["sha256"]
    expected_size = int(row["size"])
    parsed = urlparse(uri)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or parsed.query or parsed.fragment:
        raise SystemExit(f"unsupported package URI shape for {row['package']}")
    if not (host in {"archive.ubuntu.com", "security.ubuntu.com"} or host.endswith(".archive.ubuntu.com")):
        raise SystemExit(f"non-Ubuntu package host requires review: {host}")
    if not filename_re.fullmatch(filename) or Path(filename).name != filename:
        raise SystemExit(f"unsafe package filename: {filename}")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
        raise SystemExit(f"invalid expected SHA256 for {filename}")
    target = package_dir / filename
    partial = package_dir / f"{filename}.partial"
    if target.exists():
        actual_sha = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual_sha == expected_sha and target.stat().st_size == expected_size:
            print(f"reuse_verified_package={row['package']}")
            continue
        target.unlink()
    subprocess.check_call(
        [
            "curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
            "--proto", "=http,https", uri, "--output", str(partial),
        ]
    )
    actual_sha = hashlib.sha256(partial.read_bytes()).hexdigest()
    actual_size = partial.stat().st_size
    if actual_sha != expected_sha or actual_size != expected_size:
        partial.unlink(missing_ok=True)
        raise SystemExit(f"package verification failed for {filename}")
    partial.replace(target)
    print(f"download_verified_package={row['package']}")
PY
emit 'milestone=local_package_download;state=pass'

emit 'milestone=package_inspection;state=start'
license_manifest="$artifact_dir/license_manifest.tsv"
printf 'package\tversion\tcopyright_status\tartifact\n' >"$license_manifest"
for deb_path in "$artifact_dir"/packages/*.deb; do
  package="$(dpkg-deb -f "$deb_path" Package)"
  version="$(dpkg-deb -f "$deb_path" Version)"
  architecture="$(dpkg-deb -f "$deb_path" Architecture)"
  safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._+-' '_')"
  dpkg-deb -c "$deb_path" >"$artifact_dir/package-filelists/${package}_${safe_version}_${architecture}.txt"
  extract_root="$work_root/extract-${package}-${safe_version}"
  mkdir -p -- "$extract_root"
  dpkg-deb -x "$deb_path" "$extract_root"
  copyright_count=0
  while IFS= read -r copyright_path; do
    copyright_count=$((copyright_count + 1))
    license_name="${package}_${safe_version}_${copyright_count}.copyright"
    cp --dereference -- "$copyright_path" "$artifact_dir/licenses/$license_name"
    printf '%s\t%s\tpresent\t%s\n' "$package" "$version" "$license_name" >>"$license_manifest"
  done < <(find -L "$extract_root/usr/share/doc" -type f -name copyright 2>/dev/null | sort)
  if (( copyright_count == 0 )); then
    printf '%s\t%s\tmissing\t-\n' "$package" "$version" >>"$license_manifest"
  fi
  rm -rf -- "$extract_root"
done
emit 'milestone=package_inspection;state=pass'

emit 'milestone=public_advisory_capture;state=deferred_to_separate_review'
advisory_pending_count=3
printf 'label\turl\tartifact\tstatus\n' >"$artifact_dir/advisories/source_manifest.tsv"
printf '%s\t%s\t-\tdeferred\n' \
  postgresql 'https://ubuntu.com/security/notices?details=postgresql-16' \
  >>"$artifact_dir/advisories/source_manifest.tsv"
printf '%s\t%s\t-\tdeferred\n' \
  pgvector 'https://ubuntu.com/security/notices?details=pgvector' \
  >>"$artifact_dir/advisories/source_manifest.tsv"
printf '%s\t%s\t-\tdeferred\n' \
  psycopg3 'https://ubuntu.com/security/notices?details=psycopg3' \
  >>"$artifact_dir/advisories/source_manifest.tsv"
emit 'milestone=public_advisory_capture;state=pending;deferred_count=3;network_contact=false'

python3 - "$download_manifest" "$artifact_dir/packages" "$artifact_dir/package_register.tsv" <<'PY'
from __future__ import annotations

import csv
import hashlib
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
package_dir = Path(sys.argv[2])
register_path = Path(sys.argv[3])
rows = list(csv.DictReader(metadata_path.open(encoding="utf-8"), delimiter="\t"))
columns = [
    "root_or_dependency", "package", "version", "architecture", "local_filename",
    "size", "apt_sha256", "local_sha256", "source", "source_uri",
]
with register_path.open("w", encoding="utf-8") as handle:
    handle.write("\t".join(columns) + "\n")
    for row in rows:
        package_path = package_dir / row["local_filename"]
        local_sha = hashlib.sha256(package_path.read_bytes()).hexdigest()
        values = {
            "root_or_dependency": row["root_or_dependency"],
            "package": row["package"],
            "version": row["version"],
            "architecture": row["architecture"],
            "local_filename": row["local_filename"],
            "size": row["size"],
            "apt_sha256": row["sha256"],
            "local_sha256": local_sha,
            "source": row["source"],
            "source_uri": row["uri"],
        }
        handle.write("\t".join(values[column] for column in columns) + "\n")
PY

{
  printf 'package\tversion\taffectedness\taction_required\tdisposition\n'
  tail -n +2 "$artifact_dir/target-metadata/root_package_records.tsv" \
    | while IFS=$'\t' read -r package expected_version _rest; do
        printf '%s\t%s\tpending_review\tpending_review\tcapture_only_no_install\n' \
          "$package" "$expected_version"
      done
} >"$artifact_dir/advisory_install_gate.tsv"

{
  printf 'schema=native-postgresql-offline-package-capture/v1\n'
  printf 'label=%s\n' "$label"
  printf 'created_utc=%s\n' "$timestamp"
  printf 'target_os=ubuntu%s\n' "$expected_os_version"
  printf 'target_architecture=amd64\n'
  printf 'root_package_count=%s\n' "${#root_specs[@]}"
  printf 'captured_package_count=%s\n' "$(find "$artifact_dir/packages" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ')"
  printf 'advisory_affectedness=pending_review\n'
  printf 'advisory_source_pending_count=%s\n' "$advisory_pending_count"
  printf 'install_authorized=false\n'
  printf 'remote_package_download=false\n'
  printf 'package_install=false\n'
  printf 'database_initialization=false\n'
  printf 'service_mutation=false\n'
} >"$artifact_dir/capture_summary.env"

(
  cd "$artifact_dir"
  find . -type f ! -name SHA256SUMS -printf '%P\t%s\n' | sort >artifact_manifest.tsv
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
  sha256sum -c SHA256SUMS
)

tar -C "$artifact_root" -czf "$bundle_path" "$label"
bundle_sha256="$(sha256sum "$bundle_path" | awk '{print $1}')"
printf '%s  %s\n' "$bundle_sha256" "$(basename "$bundle_path")" >"$bundle_sidecar"

emit "artifact_directory=$artifact_dir"
emit "offline_bundle=$bundle_path;bundle_sha256=$bundle_sha256"
emit "package_count=$(find "$artifact_dir/packages" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ')"
emit "advisory_affectedness=pending_review;advisory_source_pending_count=$advisory_pending_count;install_authorized=false"
emit 'native_postgresql_package_capture=pass_with_advisory_sources_pending;next_gate=review_advisories_separately_before_target_transfer_or_install'
