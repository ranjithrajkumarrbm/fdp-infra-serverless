#!/usr/bin/env bash
###############################################################################
# Build step: package the Lambda's Python sources into a deployable zip.
#
#   ./scripts/package.sh [output-zip]
#
# Default output: build/transaction_processor.zip
#
# Terraform also packages the same `src/` tree via `data "archive_file"` during
# `plan`/`apply`, so `terraform apply` alone is enough to deploy. This script is
# for CI's explicit build stage (syntax gate + published artifact) and for
# manual `aws lambda update-function-code` deploys.
#
# boto3 ships in the Lambda Python runtime, so there is nothing to vendor. If a
# third-party dependency is ever added, install it into the staging dir here
# (`pip install -r src/requirements.txt -t "$STAGE"`).
###############################################################################
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src"
OUT_ZIP="${1:-${ROOT_DIR}/build/transaction_processor.zip}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Byte-compiling sources (syntax gate)"
python3 -m compileall -q "${SRC_DIR}"

echo "==> Staging sources"
rsync -a --exclude '__pycache__' --exclude '*.pyc' "${SRC_DIR}/" "${STAGE}/"

echo "==> Writing ${OUT_ZIP}"
mkdir -p "$(dirname "${OUT_ZIP}")"
rm -f "${OUT_ZIP}"
( cd "${STAGE}" && zip -qr -X "${OUT_ZIP}" . )

echo "==> Done"
unzip -l "${OUT_ZIP}"
