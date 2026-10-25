#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Replace the blocked Ubuntu Noble pgvector 0.6.0 package with the reviewed
#   native pgvector 0.8.7 package from the official signed PostgreSQL Apt
#   repository and create a new checksum-bound offline bundle.
#
# Default execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/07_capture_reviewed_pgvector_replacement_bundle.sh
#
# The script is local-only. It verifies the complete pre-download advisory
# decision set before downloading any package payload. It does not contact a
# lab host, install a package, initialize a database, or change a service.

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --source-bundle PATH       Accepted but advisory-blocked Script 06 bundle.' \
    '  --advisory-review PATH     Reviewed pre-download source/version decisions.' \
    '  --artifact-root PATH       Absolute local artifact parent.' \
    '  --report-root PATH         Absolute local report directory.' \
    '  --validate-only            Validate source and review-file structure only.' \
    '  --plan-only                Validate exact inputs and pre-download gate only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DEFAULT_SOURCE_BUNDLE="$REPO_ROOT/local/artifacts/native-postgresql-packages/native-postgresql-ubuntu24.04-amd64-20261019T030940Z.tar.gz"
readonly DEFAULT_ADVISORY_REVIEW="$PHASE_ROOT/reference/native-postgresql-advisory-review-v1.tsv"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/native-postgresql-packages"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-pgvector-replacement-capture"
readonly EXPECTED_SOURCE_BUNDLE_SHA256="7e6d63ac7f3606c871ed83ce8a9b0eb022444550483dc45cd79293e8dde0a470"
readonly PGDG_KEY_URL="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
readonly PGDG_KEY_FINGERPRINT="B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8"
readonly PGDG_REPOSITORY="https://apt.postgresql.org/pub/repos/apt"
readonly PGDG_SUITE="noble-pgdg"
readonly PGDG_PACKAGE="postgresql-16-pgvector"
readonly PGDG_VERSION="0.8.7-1.pgdg24.04+1"
readonly PGDG_ARCHITECTURE="amd64"

source_bundle="$DEFAULT_SOURCE_BUNDLE"
advisory_review="$DEFAULT_ADVISORY_REVIEW"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false
plan_only=false

while (( $# > 0 )); do
  case "$1" in
    --source-bundle) source_bundle="${2:-}"; shift 2 ;;
    --advisory-review) advisory_review="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --plan-only) plan_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for required in awk bash basename cp curl date dpkg-deb find gpg gpgv grep gzip mkdir mktemp mv python3 rm sed sha256sum sort tar tee tr wc xargs; do
  command -v "$required" >/dev/null 2>&1 \
    || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for path in "$artifact_root" "$report_root"; do
  [[ "$path" == /* && ! -L "$path" ]] \
    || { printf 'BLOCKED: artifact and report roots must be absolute non-symlinks.\n' >&2; exit 2; }
done
[[ -f "$advisory_review" && ! -L "$advisory_review" && -r "$advisory_review" ]] \
  || { printf 'BLOCKED: reviewed advisory decision file is missing or unsafe.\n' >&2; exit 2; }

expected_review_coordinates=(
  $'libjson-perl\t4.10000-1\taccepted'
  $'postgresql-common\t257build1.1\taccepted'
  $'llvm-toolchain-17\t1:17.0.6-9ubuntu1\taccepted_not_applicable'
  $'postgresql-16\t16.15-0ubuntu0.24.04.1\taccepted_fixed'
  $'psycopg3\t3.1.17-2\taccepted'
  $'pgvector\t0.8.7-1.pgdg24.04+1\taccepted_fixed'
)

python3 - "$advisory_review" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
required = {"source_package", "version", "target", "decision", "finding", "references"}
if not rows or not required.issubset(rows[0]):
    raise SystemExit("advisory review is empty or has an invalid schema")
seen: set[tuple[str, str]] = set()
for row in rows:
    coordinate = (row["source_package"], row["version"])
    if coordinate in seen:
        raise SystemExit(f"duplicate advisory coordinate: {coordinate}")
    seen.add(coordinate)
    if row["target"] != "ubuntu24.04-amd64":
        raise SystemExit(f"unexpected advisory target for {coordinate}")
    if row["decision"] not in {"accepted", "accepted_fixed", "accepted_not_applicable"}:
        raise SystemExit(f"unaccepted advisory decision for {coordinate}")
    if not row["finding"].strip() or not row["references"].startswith("https://"):
        raise SystemExit(f"incomplete advisory evidence for {coordinate}")
PY

for coordinate in "${expected_review_coordinates[@]}"; do
  IFS=$'\t' read -r source version decision <<<"$coordinate"
  awk -F '\t' -v source="$source" -v version="$version" -v decision="$decision" '
    NR > 1 && $1 == source && $2 == version && $3 == "ubuntu24.04-amd64" && $4 == decision {count++}
    END {exit(count == 1 ? 0 : 1)}
  ' "$advisory_review" \
    || { printf 'BLOCKED: required reviewed advisory coordinate is absent: %s=%s\n' "$source" "$version" >&2; exit 2; }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
review_sha256="$(sha256sum "$advisory_review" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'reviewed_pgvector_replacement_source=pass' \
    'target_contact=false' \
    'package_download=false' \
    "script_sha256=$script_sha256" \
    "advisory_review_sha256=$review_sha256" \
    'pre_download_advisory_gate=pass'
  exit 0
fi

[[ -f "$source_bundle" && ! -L "$source_bundle" && -r "$source_bundle" ]] \
  || { printf 'BLOCKED: accepted Script 06 source bundle is missing or unsafe.\n' >&2; exit 2; }
source_bundle_sha256="$(sha256sum "$source_bundle" | awk '{print $1}')"
[[ "$source_bundle_sha256" == "$EXPECTED_SOURCE_BUNDLE_SHA256" ]] \
  || { printf 'BLOCKED: Script 06 source bundle checksum does not match accepted evidence.\n' >&2; exit 2; }
tar -tzf "$source_bundle" | grep -Eq '(^/|(^|/)\.\.(/|$))' \
  && { printf 'BLOCKED: Script 06 source bundle contains an unsafe path.\n' >&2; exit 2; }

if [[ "$plan_only" == true ]]; then
  printf '%s\n' \
    'reviewed_pgvector_replacement_plan=pass' \
    'target_contact=false' \
    'package_download=false' \
    'pre_download_advisory_gate=pass' \
    "source_bundle_sha256=$source_bundle_sha256" \
    "replacement_coordinate=$PGDG_PACKAGE=$PGDG_VERSION" \
    "advisory_review_sha256=$review_sha256"
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
label="native-postgresql-ubuntu24.04-amd64-pgvector0.8.7-${timestamp}"
artifact_dir="$artifact_root/$label"
bundle_path="$artifact_root/${label}.tar.gz"
bundle_sidecar="$bundle_path.sha256"
report_path="$(mktemp "$report_root/native_postgresql_pgvector_replacement_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-pgvector-replacement.XXXXXX)"
[[ ! -e "$artifact_dir" && ! -e "$bundle_path" && ! -e "$bundle_sidecar" ]] \
  || { printf 'BLOCKED: replacement capture target already exists.\n' >&2; exit 2; }

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/native-postgresql-pgvector-replacement.* && -d "$work_root" ]]; then
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

record_unexpected_failure() {
  local status="$1" line="$2"
  trap - ERR
  set +e
  printf 'reviewed_pgvector_replacement_capture=blocked;reason=unexpected_local_failure;exit_code=%s;line=%s;local_report=%s\n' \
    "$status" "$line" "$report_path" | tee -a "$report_path" >&2
  exit "$status"
}
trap 'status=$?; record_unexpected_failure "$status" "$LINENO"' ERR

emit 'purpose=capture_reviewed_native_pgvector_replacement_bundle'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256"
emit "source_bundle=$(basename "$source_bundle");source_bundle_sha256=$source_bundle_sha256"
emit "advisory_review=$(basename "$advisory_review");advisory_review_sha256=$review_sha256"
emit "replacement_coordinate=$PGDG_PACKAGE=$PGDG_VERSION;architecture=$PGDG_ARCHITECTURE"
emit 'authorized_actions=download_signed_repository_metadata_download_exact_reviewed_package_payload_write_local_ignored_artifacts'
emit 'non_actions=no_target_contact_no_repository_configuration_change_no_apt_update_no_install_no_database_initialization_no_service_or_configuration_change'
emit 'milestone=pre_download_advisory_gate;state=pass;reviewed_source_count=6'

repository_dir="$work_root/repository"
mkdir -p -- "$repository_dir"
key_asc="$repository_dir/ACCC4CF8.asc"
keyring="$repository_dir/ACCC4CF8.gpg"
inrelease="$repository_dir/InRelease"
packages_gz="$repository_dir/Packages.gz"
packages_file="$repository_dir/Packages"
gpg_home="$work_root/gnupg"
mkdir -m 700 -- "$gpg_home"

emit 'milestone=signed_repository_metadata;state=start'
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
  "$PGDG_KEY_URL" --output "$key_asc"
actual_fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons --import-options show-only --import "$key_asc" 2>/dev/null \
  | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "$actual_fingerprint" == "$PGDG_KEY_FINGERPRINT" ]] \
  || { emit 'replacement_capture=blocked;reason=pgdg_key_fingerprint_mismatch'; exit 1; }
gpg --batch --yes --dearmor --output "$keyring" "$key_asc"
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
  "$PGDG_REPOSITORY/dists/$PGDG_SUITE/InRelease" --output "$inrelease"
gpgv --keyring "$keyring" "$inrelease" >"$repository_dir/inrelease-verification.txt" 2>&1 \
  || { emit 'replacement_capture=blocked;reason=pgdg_inrelease_signature_failure'; exit 1; }

packages_metadata="$(
  awk '$1 ~ /^[0-9a-f]{64}$/ && $3 == "main/binary-amd64/Packages.gz" {print $1, $2; exit}' "$inrelease"
)"
[[ -n "$packages_metadata" ]] \
  || { emit 'replacement_capture=blocked;reason=pgdg_packages_index_not_signed'; exit 1; }
read -r packages_sha256 packages_size <<<"$packages_metadata"
[[ "$packages_sha256" =~ ^[0-9a-f]{64}$ && "$packages_size" =~ ^[0-9]+$ ]] \
  || { emit 'replacement_capture=blocked;reason=pgdg_packages_index_not_signed'; exit 1; }
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
  "$PGDG_REPOSITORY/dists/$PGDG_SUITE/main/binary-amd64/Packages.gz" --output "$packages_gz"
[[ "$(sha256sum "$packages_gz" | awk '{print $1}')" == "$packages_sha256" \
    && "$(wc -c <"$packages_gz" | tr -d ' ')" == "$packages_size" ]] \
  || { emit 'replacement_capture=blocked;reason=pgdg_packages_index_checksum_failure'; exit 1; }
gzip -dc -- "$packages_gz" >"$packages_file"

selected_record="$repository_dir/selected-package.tsv"
python3 - "$packages_file" "$selected_record" "$PGDG_PACKAGE" "$PGDG_VERSION" "$PGDG_ARCHITECTURE" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

packages_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
wanted_package, wanted_version, wanted_arch = sys.argv[3:6]

records: list[dict[str, str]] = []
for paragraph in packages_path.read_text(encoding="utf-8", errors="strict").split("\n\n"):
    record: dict[str, str] = {}
    current = ""
    for line in paragraph.splitlines():
        if line.startswith((" ", "\t")) and current:
            record[current] += " " + line.strip()
        elif ": " in line:
            current, value = line.split(": ", 1)
            record[current] = value
    if record.get("Package") == wanted_package and record.get("Version") == wanted_version and record.get("Architecture") == wanted_arch:
        records.append(record)

if len(records) != 1:
    raise SystemExit(f"expected exactly one reviewed PGDG package record, found {len(records)}")
record = records[0]
required = {"Filename", "Size", "SHA256", "Depends"}
if not required.issubset(record):
    raise SystemExit("selected PGDG record lacks required signed fields")
if not re.fullmatch(r"pool/main/p/pgvector/[A-Za-z0-9.+~_-]+\.deb", record["Filename"]):
    raise SystemExit("selected PGDG package path is outside reviewed pgvector pool")
if not re.fullmatch(r"[0-9a-f]{64}", record["SHA256"]) or not record["Size"].isdigit():
    raise SystemExit("selected PGDG package has invalid signed size or checksum")
if "postgresql-16" not in record["Depends"] or "libc6" not in record["Depends"]:
    raise SystemExit("selected PGDG package dependency contract is unexpected")
source = record.get("Source", "pgvector").split(" ", 1)[0]
if source != "pgvector":
    raise SystemExit("selected PGDG package source is not pgvector")

columns = ["package", "version", "architecture", "source", "filename", "size", "sha256", "depends"]
with output_path.open("w", encoding="utf-8") as handle:
    handle.write("\t".join(columns) + "\n")
    values = {
        "package": wanted_package,
        "version": wanted_version,
        "architecture": wanted_arch,
        "source": source,
        "filename": record["Filename"],
        "size": record["Size"],
        "sha256": record["SHA256"],
        "depends": record["Depends"],
    }
    handle.write("\t".join(values[column] for column in columns) + "\n")
PY
emit 'milestone=signed_repository_metadata;state=pass;signature=verified;key_fingerprint=verified'

package_relative="$(awk -F '\t' 'NR == 2 {print $5}' "$selected_record")"
package_size="$(awk -F '\t' 'NR == 2 {print $6}' "$selected_record")"
package_sha256="$(awk -F '\t' 'NR == 2 {print $7}' "$selected_record")"
package_filename="$(basename "$package_relative")"
downloaded_package="$work_root/$package_filename"

emit 'milestone=reviewed_package_download;state=start;pre_download_advisory_gate=pass'
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' \
  "$PGDG_REPOSITORY/$package_relative" --output "$downloaded_package.partial"
[[ "$(sha256sum "$downloaded_package.partial" | awk '{print $1}')" == "$package_sha256" \
    && "$(wc -c <"$downloaded_package.partial" | tr -d ' ')" == "$package_size" ]] \
  || { emit 'replacement_capture=blocked;reason=reviewed_pgvector_package_checksum_failure'; exit 1; }
mv -- "$downloaded_package.partial" "$downloaded_package"
[[ "$(dpkg-deb -f "$downloaded_package" Package)" == "$PGDG_PACKAGE" \
    && "$(dpkg-deb -f "$downloaded_package" Version)" == "$PGDG_VERSION" \
    && "$(dpkg-deb -f "$downloaded_package" Architecture)" == "$PGDG_ARCHITECTURE" ]] \
  || { emit 'replacement_capture=blocked;reason=reviewed_pgvector_package_control_mismatch'; exit 1; }
emit 'milestone=reviewed_package_download;state=pass'

source_extract="$work_root/source-bundle"
mkdir -p -- "$source_extract"
tar -xzf "$source_bundle" -C "$source_extract"
source_root="$(find "$source_extract" -mindepth 1 -maxdepth 1 -type d -print | sort | head -n 1)"
[[ -n "$source_root" && -f "$source_root/SHA256SUMS" ]] \
  || { emit 'replacement_capture=blocked;reason=accepted_source_bundle_layout_invalid'; exit 1; }
(cd "$source_root" && sha256sum -c SHA256SUMS) >"$work_root/source-bundle-verification.txt" 2>&1 \
  || { emit 'replacement_capture=blocked;reason=accepted_source_bundle_internal_checksum_failure'; exit 1; }

mkdir -p -- "$artifact_dir/packages" "$artifact_dir/licenses" "$artifact_dir/package-filelists" \
  "$artifact_dir/advisories" "$artifact_dir/repository-metadata"
find "$source_root/packages" -maxdepth 1 -type f -name '*.deb' \
  ! -name 'postgresql-16-pgvector_0.6.0-1_amd64.deb' -exec cp -- '{}' "$artifact_dir/packages/" \;
cp -- "$downloaded_package" "$artifact_dir/packages/$package_filename"
cp -- "$advisory_review" "$artifact_dir/advisories/review.tsv"
cp -- "$key_asc" "$inrelease" "$packages_gz" "$selected_record" \
  "$repository_dir/inrelease-verification.txt" "$artifact_dir/repository-metadata/"

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

python3 - "$source_root/package_register.tsv" "$artifact_dir/packages" "$selected_record" "$artifact_dir/package_register.tsv" <<'PY'
from __future__ import annotations

import csv
import hashlib
import sys
from pathlib import Path

old_register = Path(sys.argv[1])
package_dir = Path(sys.argv[2])
selected_record = Path(sys.argv[3])
output = Path(sys.argv[4])

old_rows = list(csv.DictReader(old_register.open(encoding="utf-8"), delimiter="\t"))
old_by_package = {row["package"]: row for row in old_rows if row["package"] != "postgresql-16-pgvector"}
pgvector = next(csv.DictReader(selected_record.open(encoding="utf-8"), delimiter="\t"))
columns = [
    "root_or_dependency", "package", "version", "architecture", "local_filename",
    "size", "repository_sha256", "local_sha256", "source", "source_uri",
]
rows: list[dict[str, str]] = []
for path in sorted(package_dir.glob("*.deb")):
    local_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if path.name == Path(pgvector["filename"]).name:
        rows.append({
            "root_or_dependency": "root",
            "package": pgvector["package"],
            "version": pgvector["version"],
            "architecture": pgvector["architecture"],
            "local_filename": path.name,
            "size": pgvector["size"],
            "repository_sha256": pgvector["sha256"],
            "local_sha256": local_sha,
            "source": pgvector["source"],
            "source_uri": "https://apt.postgresql.org/pub/repos/apt/" + pgvector["filename"],
        })
        continue
    matching = [row for row in old_by_package.values() if row["local_filename"] == path.name]
    if len(matching) != 1:
        raise SystemExit(f"source register mismatch for {path.name}")
    old = matching[0]
    rows.append({
        "root_or_dependency": old["root_or_dependency"],
        "package": old["package"],
        "version": old["version"],
        "architecture": old["architecture"],
        "local_filename": old["local_filename"],
        "size": old["size"],
        "repository_sha256": old["apt_sha256"],
        "local_sha256": local_sha,
        "source": old["source"],
        "source_uri": old["source_uri"],
    })

if len(rows) != 9 or sum(row["package"] == "postgresql-16-pgvector" for row in rows) != 1:
    raise SystemExit("replacement package set is not exactly nine packages with one pgvector")
if any(row["repository_sha256"] != row["local_sha256"] for row in rows):
    raise SystemExit("replacement package register contains a checksum mismatch")
with output.open("w", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY

{
  printf 'schema=native-postgresql-reviewed-replacement-capture/v1\n'
  printf 'label=%s\n' "$label"
  printf 'created_utc=%s\n' "$timestamp"
  printf 'target_os=ubuntu24.04\n'
  printf 'target_architecture=amd64\n'
  printf 'captured_package_count=9\n'
  printf 'pgvector_version=%s\n' "$PGDG_VERSION"
  printf 'pre_download_advisory_gate=pass\n'
  printf 'advisory_reviewed_source_count=6\n'
  printf 'package_payload_download_after_advisory_gate=true\n'
  printf 'install_authorized=false\n'
  printf 'target_contact=false\n'
  printf 'package_install=false\n'
  printf 'database_initialization=false\n'
  printf 'service_mutation=false\n'
} >"$artifact_dir/capture_summary.env"

{
  printf 'schema=native-postgresql-reviewed-replacement-provenance/v1\n'
  printf 'source_bundle=%s\n' "$(basename "$source_bundle")"
  printf 'source_bundle_sha256=%s\n' "$source_bundle_sha256"
  printf 'advisory_review_sha256=%s\n' "$review_sha256"
  printf 'pgdg_key_fingerprint=%s\n' "$PGDG_KEY_FINGERPRINT"
  printf 'pgdg_suite=%s\n' "$PGDG_SUITE"
  printf 'pgvector_coordinate=%s=%s\n' "$PGDG_PACKAGE" "$PGDG_VERSION"
} >"$artifact_dir/capture_provenance.env"

(
  cd "$artifact_dir"
  find . -type f ! -name SHA256SUMS -printf '%P\t%s\n' | sort >artifact_manifest.tsv
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
  sha256sum -c SHA256SUMS
) >"$work_root/internal-checksums.txt"

tar -C "$artifact_root" -czf "$bundle_path" "$label"
bundle_sha256="$(sha256sum "$bundle_path" | awk '{print $1}')"
printf '%s  %s\n' "$bundle_sha256" "$(basename "$bundle_path")" >"$bundle_sidecar"

emit "artifact_directory=$artifact_dir"
emit "offline_bundle=$bundle_path;bundle_sha256=$bundle_sha256"
emit 'package_count=9;advisory_reviewed_source_count=6;pre_download_advisory_gate=pass'
emit 'install_authorized=false;next_gate=review_replacement_capture_before_transfer_or_install'
emit 'reviewed_pgvector_replacement_capture=pass'
