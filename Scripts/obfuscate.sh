#!/usr/bin/env bash
set -euo pipefail

# Обфускация символов SwiftShield на этапе сборки основного Xcode-проекта.
# SPM-пакет Alamofire подключается как зависимость — запускать из корня .xcodeproj.
#
# Установка: brew install swiftshield
# Использование:
#   ./Scripts/obfuscate.sh /path/to/YourApp.xcodeproj YourAppScheme

PROJECT_PATH="${1:?Укажите путь к .xcodeproj}"
SCHEME="${2:?Укажите scheme}"

swiftshield obfuscate \
  --project-file "$PROJECT_PATH" \
  --scheme "$SCHEME" \
  --ignore-public \
  --verbose
