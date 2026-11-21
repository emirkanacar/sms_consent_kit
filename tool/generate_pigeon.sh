#!/usr/bin/env bash
# Regenerates the Pigeon bridge. CI checks that the output matches the
# committed files via `git diff --exit-code`.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run pigeon --input pigeon/messages.dart
dart format lib/src/transport/messages.g.dart
