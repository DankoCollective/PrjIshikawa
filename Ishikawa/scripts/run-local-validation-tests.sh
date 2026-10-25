#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ishikawa_root="$(cd -- "${script_dir}/.." && pwd -P)"
python_root="${ishikawa_root}/application/python"
test_root="${ishikawa_root}/tests"

python3 -c 'import sys, yaml; assert sys.version_info >= (3, 12); assert yaml.__version__'
python3 -c 'import pathlib, sys; [compile(path.read_text(encoding="utf-8"), str(path), "exec") for path in pathlib.Path(sys.argv[1]).glob("*.py")]' \
  "${python_root}/ishikawa"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="${python_root}" python3 -m unittest discover \
  --start-directory "${test_root}" \
  --pattern 'test_*.py' \
  --verbose

printf '%s\n' 'ishikawa_local_validation_tests=PASS'
