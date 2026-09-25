#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${1:?Укажите путь к .xcodeproj}"
SCHEME="${2:?Укажите scheme}"

swiftshield obfuscate \
  --project-file "$PROJECT_PATH" \
  --scheme "$SCHEME" \
  --ignore-public \
  --verbose
