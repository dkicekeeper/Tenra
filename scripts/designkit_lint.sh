#!/usr/bin/env bash
# DesignKit's design checks at the version Tenra builds with (DesignKit's
# scripts/designkit_lint.py, since 8.9.0; it replaced scripts/design_lint.py and
# scripts/section_rows_lint.py, with the same rules):
#   tokens        no raw design values beyond scripts/design-lint-baseline.json, no .swipeActions,
#                 no system Form; a justified exception: // design-lint:ignore <reason>
#   section-rows  rows of a glass section pad themselves and keep their divider under their text;
#                 a justified exception: // section-rows-lint:ignore <reason> on the row's first line
#
#   scripts/designkit_lint.sh                            # both (CI's design-lint job)
#   scripts/designkit_lint.sh tokens --report            # every hit, by rule
#   scripts/designkit_lint.sh tokens --update-baseline   # lower the baseline after a cleanup
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -A3 'repositoryURL = "https://github.com/dkicekeeper/DesignKit' Tenra.xcodeproj/project.pbxproj \
  | sed -nE 's/.*version = "?([0-9]+\.[0-9]+\.[0-9]+)"?;.*/\1/p' | head -1)
if [ -z "$VERSION" ]; then
  echo "No exact DesignKit version in Tenra.xcodeproj/project.pbxproj" >&2
  exit 1
fi
SCRIPT="${TMPDIR:-/tmp}/designkit_lint-$VERSION.py"
if [ ! -s "$SCRIPT" ]; then
  curl -fsSL "https://raw.githubusercontent.com/dkicekeeper/DesignKit/$VERSION/scripts/designkit_lint.py" -o "$SCRIPT"
fi

CHECK="${1:-all}"
[ $# -gt 0 ] && shift
exec python3 "$SCRIPT" "$CHECK" --source Tenra "$@"
