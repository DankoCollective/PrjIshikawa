#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Replace the incompatible Ubuntu PostgreSQL/JIT pair with the reviewed
#   PGDG PostgreSQL 16 server and Ubuntu libllvm19, then create one compatible
#   checksum-bound offline bundle.
#
# Default execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/10_capture_compatible_native_postgresql_bundle.sh
#
# This script is local-only. It does not contact a lab host, install a package,
# initialize a database, or change a service.

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --source-bundle PATH       Compatibility-blocked Script 07 bundle.' \
    '  --compatibility-report PATH  Accepted Script 09 report.' \
    '  --advisory-review PATH     Reviewed compatible decision set.' \
    '  --artifact-root PATH       Absolute local artifact parent.' \
    '  --report-root PATH         Absolute local report directory.' \
    '  --validate-only            Validate source identities and review schema.' \
    '  --plan-only                Verify all local gates without package download.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DEFAULT_SOURCE_BUNDLE="$REPO_ROOT/local/artifacts/native-postgresql-packages/native-postgresql-ubuntu24.04-amd64-pgvector0.8.7-20261019T035159Z.tar.gz"
readonly DEFAULT_COMPATIBILITY_REPORT="$REPO_ROOT/local/reports/native-postgresql-compatibility-inventory/native_postgresql_compatibility_inventory_20261019T131350Z_UIXF4r.txt"
readonly DEFAULT_ADVISORY_REVIEW="$PHASE_ROOT/reference/native-postgresql-advisory-review-v2.tsv"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/native-postgresql-packages"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-compatible-capture"
readonly EXPECTED_SOURCE_BUNDLE_SHA256="d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5"
readonly EXPECTED_COMPATIBILITY_REPORT_SHA256="25f3f939b05b71a3ac426edc5ad4adf1ce353ab438135731a031241e87115d54"
readonly PGDG_KEY_FINGERPRINT="B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8"
readonly PGDG_REPOSITORY="https://apt.postgresql.org/pub/repos/apt"
readonly PGDG_SUITE="noble-pgdg"
readonly PGDG_SERVER_PACKAGE="postgresql-16"
readonly PGDG_SERVER_VERSION="16.15-1.pgdg24.04+2"
readonly PGDG_SERVER_ARCHITECTURE="amd64"
readonly PGDG_SERVER_FILENAME="pool/main/p/postgresql-16/postgresql-16_16.15-1.pgdg24.04+2_amd64.deb"
readonly PGDG_SERVER_SIZE="16424836"
readonly PGDG_SERVER_SHA256="abe560fc574383f520753dfaef79ab24081cda488293d5c991a9f77ac98ef18f"
readonly LLVM_PACKAGE="libllvm19"
readonly LLVM_VERSION="1:19.1.1-1ubuntu1~24.04.2"
readonly LLVM_ARCHITECTURE="amd64"
readonly LLVM_SOURCE="llvm-toolchain-19"
readonly LLVM_FILENAME="pool/main/l/llvm-toolchain-19/libllvm19_19.1.1-1ubuntu1~24.04.2_amd64.deb"
readonly LLVM_SIZE="28737618"
readonly LLVM_SHA256="a62f1074eb7aecf10e00fed9c7c967dc6c801fae444a40b8007e246320f5ee15"
readonly UBUNTU_SECURITY_REPOSITORY="https://security.ubuntu.com/ubuntu"

source_bundle="$DEFAULT_SOURCE_BUNDLE"
compatibility_report="$DEFAULT_COMPATIBILITY_REPORT"
advisory_review="$DEFAULT_ADVISORY_REVIEW"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false
plan_only=false

while (( $# > 0 )); do
  case "$1" in
    --source-bundle) source_bundle="${2:-}"; shift 2 ;;
    --compatibility-report) compatibility_report="${2:-}"; shift 2 ;;
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
for path in "$source_bundle" "$compatibility_report" "$advisory_review"; do
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || { printf 'BLOCKED: required accepted input is missing or unsafe: %s\n' "$path" >&2; exit 2; }
done

source_bundle_sha256="$(sha256sum "$source_bundle" | awk '{print $1}')"
compatibility_report_sha256="$(sha256sum "$compatibility_report" | awk '{print $1}')"
[[ "$source_bundle_sha256" == "$EXPECTED_SOURCE_BUNDLE_SHA256" ]] \
  || { printf 'BLOCKED: Script 07 source bundle checksum mismatch.\n' >&2; exit 2; }
[[ "$compatibility_report_sha256" == "$EXPECTED_COMPATIBILITY_REPORT_SHA256" ]] \
  || { printf 'BLOCKED: Script 09 compatibility report checksum mismatch.\n' >&2; exit 2; }
grep -Fqx "package_libllvm19=observed;name=$LLVM_PACKAGE;installed_version=$LLVM_VERSION;candidate_version=$LLVM_VERSION;architecture=$LLVM_ARCHITECTURE;source=$LLVM_SOURCE;filename=$LLVM_FILENAME;size=$LLVM_SIZE;sha256=$LLVM_SHA256" "$compatibility_report" \
  || { printf 'BLOCKED: Script 09 report does not contain the accepted libllvm19 coordinate.\n' >&2; exit 2; }

python3 - "$advisory_review" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
required = {"source_package", "version", "origin", "target", "decision", "finding", "references"}
if not rows or not required.issubset(rows[0]):
    raise SystemExit("advisory review is empty or has an invalid schema")
expected = {
    ("libjson-perl", "4.10000-1", "ubuntu-noble", "accepted"),
    ("postgresql-common", "257build1.1", "ubuntu-noble", "accepted"),
    ("llvm-toolchain-19", "1:19.1.1-1ubuntu1~24.04.2", "ubuntu-noble", "accepted_not_applicable"),
    ("postgresql-16", "16.15-0ubuntu0.24.04.1", "ubuntu-noble", "accepted_fixed"),
    ("postgresql-16", "16.15-1.pgdg24.04+2", "postgresql-apt-noble-pgdg", "accepted_fixed"),
    ("psycopg3", "3.1.17-2", "ubuntu-noble", "accepted"),
    ("pgvector", "0.8.7-1.pgdg24.04+1", "postgresql-apt-noble-pgdg", "accepted_fixed"),
}
observed: set[tuple[str, str, str, str]] = set()
for row in rows:
    coordinate = (row["source_package"], row["version"], row["origin"], row["decision"])
    if coordinate in observed:
        raise SystemExit(f"duplicate advisory coordinate: {coordinate}")
    observed.add(coordinate)
    if row["target"] != "ubuntu24.04-amd64":
        raise SystemExit(f"unexpected advisory target for {coordinate}")
    if row["decision"] not in {"accepted", "accepted_fixed", "accepted_not_applicable"}:
        raise SystemExit(f"unaccepted advisory decision for {coordinate}")
    if not row["finding"].strip() or not row["references"].startswith("https://"):
        raise SystemExit(f"incomplete advisory evidence for {coordinate}")
if observed != expected:
    missing = expected - observed
    extra = observed - expected
    raise SystemExit(f"advisory coordinates differ from accepted set; missing={missing}; extra={extra}")
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
review_sha256="$(sha256sum "$advisory_review" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'compatible_native_postgresql_capture_source=pass' \
    'target_contact=false' \
    'package_download=false' \
    'package_install=false' \
    "script_sha256=$script_sha256" \
    "source_bundle_sha256=$source_bundle_sha256" \
    "compatibility_report_sha256=$compatibility_report_sha256" \
    "advisory_review_sha256=$review_sha256" \
    'pre_download_advisory_gate=pass'
  exit 0
fi

tar -tzf "$source_bundle" | grep -Eq '(^/|(^|/)\.\.(/|$))' \
  && { printf 'BLOCKED: Script 07 bundle contains an unsafe path.\n' >&2; exit 2; }

work_root="$(mktemp -d /tmp/native-postgresql-compatible-capture.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/native-postgresql-compatible-capture.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_extract="$work_root/source-bundle"
mkdir -p -- "$source_extract"
tar -xzf "$source_bundle" -C "$source_extract"
source_root="$(find "$source_extract" -mindepth 1 -maxdepth 1 -type d -print | sort | head -n 1)"
[[ -n "$source_root" && -f "$source_root/SHA256SUMS" ]] \
  || { printf 'BLOCKED: Script 07 bundle layout is invalid.\n' >&2; exit 2; }
(cd "$source_root" && sha256sum -c SHA256SUMS) >"$work_root/source-bundle-verification.txt" 2>&1 \
  || { printf 'BLOCKED: Script 07 internal checksum verification failed.\n' >&2; exit 2; }

repository_dir="$source_root/repository-metadata"
key_asc="$repository_dir/ACCC4CF8.asc"
inrelease="$repository_dir/InRelease"
packages_gz="$repository_dir/Packages.gz"
for path in "$key_asc" "$inrelease" "$packages_gz"; do
  [[ -f "$path" && ! -L "$path" ]] \
    || { printf 'BLOCKED: required captured signed PGDG metadata is missing.\n' >&2; exit 2; }
done

gpg_home="$work_root/gnupg"
keyring="$work_root/ACCC4CF8.gpg"
mkdir -m 700 -- "$gpg_home"
actual_fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons --import-options show-only --import "$key_asc" 2>/dev/null \
  | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "$actual_fingerprint" == "$PGDG_KEY_FINGERPRINT" ]] \
  || { printf 'BLOCKED: captured PGDG key fingerprint mismatch.\n' >&2; exit 2; }
gpg --batch --yes --dearmor --output "$keyring" "$key_asc"
gpgv --keyring "$keyring" "$inrelease" >"$work_root/inrelease-verification.txt" 2>&1 \
  || { printf 'BLOCKED: captured PGDG InRelease signature failed.\n' >&2; exit 2; }

packages_metadata="$(awk '$1 ~ /^[0-9a-f]{64}$/ && $3 == "main/binary-amd64/Packages.gz" {print $1, $2; exit}' "$inrelease")"
[[ -n "$packages_metadata" ]] \
  || { printf 'BLOCKED: signed PGDG package-index coordinate is absent.\n' >&2; exit 2; }
read -r packages_sha256 packages_size <<<"$packages_metadata"
[[ "$(sha256sum "$packages_gz" | awk '{print $1}')" == "$packages_sha256" \
    && "$(wc -c <"$packages_gz" | tr -d ' ')" == "$packages_size" ]] \
  || { printf 'BLOCKED: captured PGDG package-index checksum mismatch.\n' >&2; exit 2; }
gzip -dc -- "$packages_gz" >"$work_root/Packages"

selected_server_record="$work_root/selected-postgresql-package.tsv"
python3 - "$work_root/Packages" "$selected_server_record" "$PGDG_SERVER_PACKAGE" "$PGDG_SERVER_VERSION" "$PGDG_SERVER_ARCHITECTURE" <<'PY'
from __future__ import annotations

import csv
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
    raise SystemExit(f"expected one signed PGDG PostgreSQL record, found {len(records)}")
record = records[0]
required = {"Filename", "Size", "SHA256", "Depends", "Provides"}
if not required.issubset(record):
    raise SystemExit("signed PGDG PostgreSQL record lacks required fields")
if not re.fullmatch(r"pool/main/p/postgresql-16/[A-Za-z0-9.+~_-]+\.deb", record["Filename"]):
    raise SystemExit("PGDG PostgreSQL path is outside the reviewed pool")
if "libllvm19" not in record["Depends"] or "postgresql-client-16" not in record["Depends"]:
    raise SystemExit("PGDG PostgreSQL dependency contract is unexpected")
if "postgresql-16-jit-llvm (= 19)" not in record["Provides"]:
    raise SystemExit("PGDG PostgreSQL does not provide reviewed JIT version 19")
columns = ["package", "version", "architecture", "source", "filename", "size", "sha256", "depends", "provides"]
values = {
    "package": wanted_package,
    "version": wanted_version,
    "architecture": wanted_arch,
    "source": record.get("Source", wanted_package).split(" ", 1)[0],
    "filename": record["Filename"],
    "size": record["Size"],
    "sha256": record["SHA256"],
    "depends": record["Depends"],
    "provides": record["Provides"],
}
with output_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerow(values)
PY

[[ "$(awk -F '\t' 'NR == 2 {print $5}' "$selected_server_record")" == "$PGDG_SERVER_FILENAME" \
    && "$(awk -F '\t' 'NR == 2 {print $6}' "$selected_server_record")" == "$PGDG_SERVER_SIZE" \
    && "$(awk -F '\t' 'NR == 2 {print $7}' "$selected_server_record")" == "$PGDG_SERVER_SHA256" ]] \
  || { printf 'BLOCKED: signed PGDG PostgreSQL coordinate changed from review.\n' >&2; exit 2; }

if [[ "$plan_only" == true ]]; then
  printf '%s\n' \
    'compatible_native_postgresql_capture_plan=pass' \
    'target_contact=false' \
    'package_download=false' \
    'package_install=false' \
    'pre_download_advisory_gate=pass' \
    "source_bundle_sha256=$source_bundle_sha256" \
    "compatibility_report_sha256=$compatibility_report_sha256" \
    "advisory_review_sha256=$review_sha256" \
    "postgresql_replacement=$PGDG_SERVER_PACKAGE=$PGDG_SERVER_VERSION" \
    "llvm_replacement=$LLVM_PACKAGE=$LLVM_VERSION"
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
label="native-postgresql-ubuntu24.04-amd64-pg16.15-pgvector0.8.7-compatible-${timestamp}"
artifact_dir="$artifact_root/$label"
bundle_path="$artifact_root/${label}.tar.gz"
bundle_sidecar="$bundle_path.sha256"
report_path="$(mktemp "$report_root/native_postgresql_compatible_capture_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_dir" && ! -e "$bundle_path" && ! -e "$bundle_sidecar" ]] \
  || { printf 'BLOCKED: compatible capture target already exists.\n' >&2; exit 2; }

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

record_unexpected_failure() {
  local status="$1" line="$2"
  trap - ERR
  set +e
  printf 'compatible_native_postgresql_capture=blocked;reason=unexpected_local_failure;exit_code=%s;line=%s;local_report=%s\n' \
    "$status" "$line" "$report_path" | tee -a "$report_path" >&2
  exit "$status"
}
trap 'status=$?; record_unexpected_failure "$status" "$LINENO"' ERR

emit 'purpose=capture_compatible_native_postgresql_pgvector_psycopg_bundle'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256"
emit "source_bundle=$(basename "$source_bundle");source_bundle_sha256=$source_bundle_sha256"
emit "compatibility_report=$(basename "$compatibility_report");compatibility_report_sha256=$compatibility_report_sha256"
emit "advisory_review=$(basename "$advisory_review");advisory_review_sha256=$review_sha256"
emit "postgresql_replacement=$PGDG_SERVER_PACKAGE=$PGDG_SERVER_VERSION;llvm_replacement=$LLVM_PACKAGE=$LLVM_VERSION"
emit 'authorized_actions=download_two_exact_reviewed_package_payloads_write_local_ignored_artifacts'
emit 'non_actions=no_target_contact_no_repository_configuration_change_no_apt_update_no_install_no_database_initialization_no_service_or_configuration_change'
emit 'milestone=pre_download_advisory_and_signed_metadata_gate;state=pass;reviewed_source_count=7'

server_filename="$(basename "$PGDG_SERVER_FILENAME")"
llvm_filename="$(basename "$LLVM_FILENAME")"
downloaded_server="$work_root/$server_filename"
downloaded_llvm="$work_root/$llvm_filename"

emit 'milestone=reviewed_package_download;state=start;package_count=2'
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 --proto '=https' \
  "$PGDG_REPOSITORY/$PGDG_SERVER_FILENAME" --output "$downloaded_server.partial"
[[ "$(sha256sum "$downloaded_server.partial" | awk '{print $1}')" == "$PGDG_SERVER_SHA256" \
    && "$(wc -c <"$downloaded_server.partial" | tr -d ' ')" == "$PGDG_SERVER_SIZE" ]] \
  || { emit 'compatible_capture=blocked;reason=postgresql_payload_checksum_failure'; exit 1; }
mv -- "$downloaded_server.partial" "$downloaded_server"

curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 --proto '=https' \
  "$UBUNTU_SECURITY_REPOSITORY/$LLVM_FILENAME" --output "$downloaded_llvm.partial"
[[ "$(sha256sum "$downloaded_llvm.partial" | awk '{print $1}')" == "$LLVM_SHA256" \
    && "$(wc -c <"$downloaded_llvm.partial" | tr -d ' ')" == "$LLVM_SIZE" ]] \
  || { emit 'compatible_capture=blocked;reason=libllvm19_payload_checksum_failure'; exit 1; }
mv -- "$downloaded_llvm.partial" "$downloaded_llvm"

[[ "$(dpkg-deb -f "$downloaded_server" Package)" == "$PGDG_SERVER_PACKAGE" \
    && "$(dpkg-deb -f "$downloaded_server" Version)" == "$PGDG_SERVER_VERSION" \
    && "$(dpkg-deb -f "$downloaded_server" Architecture)" == "$PGDG_SERVER_ARCHITECTURE" \
    && "$(dpkg-deb -f "$downloaded_server" Provides)" == *'postgresql-16-jit-llvm (= 19)'* \
    && "$(dpkg-deb -f "$downloaded_server" Depends)" == *'libllvm19'* ]] \
  || { emit 'compatible_capture=blocked;reason=postgresql_payload_control_mismatch'; exit 1; }
[[ "$(dpkg-deb -f "$downloaded_llvm" Package)" == "$LLVM_PACKAGE" \
    && "$(dpkg-deb -f "$downloaded_llvm" Version)" == "$LLVM_VERSION" \
    && "$(dpkg-deb -f "$downloaded_llvm" Architecture)" == "$LLVM_ARCHITECTURE" \
    && "$(dpkg-deb -f "$downloaded_llvm" Source | awk '{print $1}')" == "$LLVM_SOURCE" ]] \
  || { emit 'compatible_capture=blocked;reason=libllvm19_payload_control_mismatch'; exit 1; }
emit 'milestone=reviewed_package_download;state=pass;package_count=2'

mkdir -p -- "$artifact_dir/packages" "$artifact_dir/licenses" "$artifact_dir/package-filelists" \
  "$artifact_dir/advisories" "$artifact_dir/repository-metadata"
find "$source_root/packages" -maxdepth 1 -type f -name '*.deb' \
  ! -name 'postgresql-16_16.15-0ubuntu0.24.04.1_amd64.deb' \
  ! -name 'libllvm17t64_*' -exec cp -- '{}' "$artifact_dir/packages/" \;
cp -- "$downloaded_server" "$artifact_dir/packages/$server_filename"
cp -- "$downloaded_llvm" "$artifact_dir/packages/$llvm_filename"
cp -- "$advisory_review" "$artifact_dir/advisories/review.tsv"
cp -- "$compatibility_report" "$artifact_dir/repository-metadata/compatibility-inventory.txt"
cp -- "$key_asc" "$inrelease" "$packages_gz" "$selected_server_record" \
  "$work_root/inrelease-verification.txt" "$artifact_dir/repository-metadata/"

python3 - "$artifact_dir/packages" <<'PY'
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

package_dir = Path(sys.argv[1])
expected = {
    ("libjson-perl", "4.10000-1", "all"),
    ("libllvm19", "1:19.1.1-1ubuntu1~24.04.2", "amd64"),
    ("libpq5", "16.15-0ubuntu0.24.04.1", "amd64"),
    ("postgresql-16-pgvector", "0.8.7-1.pgdg24.04+1", "amd64"),
    ("postgresql-16", "16.15-1.pgdg24.04+2", "amd64"),
    ("postgresql-client-16", "16.15-0ubuntu0.24.04.1", "amd64"),
    ("postgresql-client-common", "257build1.1", "all"),
    ("postgresql-common", "257build1.1", "all"),
    ("python3-psycopg", "3.1.17-2", "all"),
}
observed: set[tuple[str, str, str]] = set()
for path in sorted(package_dir.glob("*.deb")):
    values = tuple(
        subprocess.check_output(["dpkg-deb", "-f", str(path), field], text=True).strip()
        for field in ("Package", "Version", "Architecture")
    )
    observed.add(values)
if observed != expected or len(list(package_dir.glob("*.deb"))) != 9:
    raise SystemExit(f"compatible package tuple mismatch; observed={sorted(observed)}")
PY

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

python3 - "$source_root/package_register.tsv" "$artifact_dir/packages" "$artifact_dir/package_register.tsv" \
  "$PGDG_SERVER_FILENAME" "$PGDG_SERVER_SIZE" "$PGDG_SERVER_SHA256" \
  "$LLVM_FILENAME" "$LLVM_SIZE" "$LLVM_SHA256" <<'PY'
from __future__ import annotations

import csv
import hashlib
import sys
from pathlib import Path

old_register = Path(sys.argv[1])
package_dir = Path(sys.argv[2])
output = Path(sys.argv[3])
server_filename, server_size, server_sha = sys.argv[4:7]
llvm_filename, llvm_size, llvm_sha = sys.argv[7:10]
old_rows = list(csv.DictReader(old_register.open(encoding="utf-8"), delimiter="\t"))
old_by_package = {
    row["package"]: row
    for row in old_rows
    if row["package"] not in {"postgresql-16", "libllvm17t64"}
}
columns = [
    "root_or_dependency", "package", "version", "architecture", "local_filename",
    "size", "repository_sha256", "local_sha256", "source", "source_uri",
]
rows: list[dict[str, str]] = []
for path in sorted(package_dir.glob("*.deb")):
    local_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if path.name == Path(server_filename).name:
        rows.append({
            "root_or_dependency": "root",
            "package": "postgresql-16",
            "version": "16.15-1.pgdg24.04+2",
            "architecture": "amd64",
            "local_filename": path.name,
            "size": server_size,
            "repository_sha256": server_sha,
            "local_sha256": local_sha,
            "source": "postgresql-16",
            "source_uri": "https://apt.postgresql.org/pub/repos/apt/" + server_filename,
        })
        continue
    if path.name == Path(llvm_filename).name:
        rows.append({
            "root_or_dependency": "dependency",
            "package": "libllvm19",
            "version": "1:19.1.1-1ubuntu1~24.04.2",
            "architecture": "amd64",
            "local_filename": path.name,
            "size": llvm_size,
            "repository_sha256": llvm_sha,
            "local_sha256": local_sha,
            "source": "llvm-toolchain-19",
            "source_uri": "https://security.ubuntu.com/ubuntu/" + llvm_filename,
        })
        continue
    old = old_by_package.get(next((row["package"] for row in old_rows if row["local_filename"] == path.name), ""))
    if old is None:
        raise SystemExit(f"source register mismatch for {path.name}")
    rows.append({column: old[column] for column in columns})
    rows[-1]["local_sha256"] = local_sha
if len(rows) != 9 or any(row["repository_sha256"] != row["local_sha256"] for row in rows):
    raise SystemExit("compatible register count or checksum failure")
with output.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY

{
  printf 'schema=native-postgresql-compatible-capture/v1\n'
  printf 'label=%s\n' "$label"
  printf 'created_utc=%s\n' "$timestamp"
  printf 'target_os=ubuntu24.04\n'
  printf 'target_architecture=amd64\n'
  printf 'captured_package_count=9\n'
  printf 'postgresql_version=%s\n' "$PGDG_SERVER_VERSION"
  printf 'pgvector_version=0.8.7-1.pgdg24.04+1\n'
  printf 'llvm_version=%s\n' "$LLVM_VERSION"
  printf 'pre_download_advisory_gate=pass\n'
  printf 'advisory_reviewed_source_count=7\n'
  printf 'install_authorized=false\n'
  printf 'target_contact=false\n'
  printf 'package_install=false\n'
  printf 'database_initialization=false\n'
  printf 'service_mutation=false\n'
} >"$artifact_dir/capture_summary.env"

{
  printf 'schema=native-postgresql-compatible-provenance/v1\n'
  printf 'source_bundle=%s\n' "$(basename "$source_bundle")"
  printf 'source_bundle_sha256=%s\n' "$source_bundle_sha256"
  printf 'compatibility_report=%s\n' "$(basename "$compatibility_report")"
  printf 'compatibility_report_sha256=%s\n' "$compatibility_report_sha256"
  printf 'advisory_review_sha256=%s\n' "$review_sha256"
  printf 'pgdg_key_fingerprint=%s\n' "$PGDG_KEY_FINGERPRINT"
  printf 'pgdg_suite=%s\n' "$PGDG_SUITE"
  printf 'postgresql_coordinate=%s=%s\n' "$PGDG_SERVER_PACKAGE" "$PGDG_SERVER_VERSION"
  printf 'llvm_coordinate=%s=%s\n' "$LLVM_PACKAGE" "$LLVM_VERSION"
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
emit 'package_count=9;downloaded_package_count=2;advisory_reviewed_source_count=7;pre_download_advisory_gate=pass'
emit 'install_authorized=false;next_gate=review_compatible_capture_before_transfer_or_install'
emit 'compatible_native_postgresql_capture=pass'
