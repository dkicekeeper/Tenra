#!/bin/zsh
#
# capture_screenshots.sh — automated App Store raw-screenshot capture.
#
# Runs TenraUITests/ScreenshotCaptureTests once per storefront locale with the
# ScreenshotDemo seeded dataset (see Tenra/Services/Utilities/ScreenshotDemo/),
# then exports the PNG attachments from each .xcresult bundle into
# screenshots/raw/<asc-locale>/.
#
# Usage:
#   ./scripts/capture_screenshots.sh            # all locales
#   ONLY=de-DE ./scripts/capture_screenshots.sh # single locale
#   SIM_NAME="iPhone 17 Pro" ./scripts/capture_screenshots.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
OUT_ROOT="screenshots/raw"
RESULTS_ROOT="build/screenshot-results"
BUNDLE_ID="dakacom.Tenra"

# asc-locale | AppleLanguages | AppleLocale | demo currency
LOCALES=(
  "de-DE|de|de_DE|EUR"
  "es-ES|es|es_ES|EUR"
  "es-MX|es-MX|es_MX|MXN"
  "fr-FR|fr|fr_FR|EUR"
  "fr-CA|fr-CA|fr_CA|CAD"
  "tr|tr|tr_TR|TRY"
  "pt-BR|pt-BR|pt_BR|BRL"
  "it|it|it_IT|EUR"
  "uk|uk|uk_UA|UAH"
  "ja|ja|ja_JP|JPY"
  "ko|ko|ko_KR|KRW"
  "en-US|en|en_US|USD"
  "ru|ru|ru_RU|KZT"
)

echo "▶ Booting simulator: $SIM_NAME"
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_NAME" -b

# Clean marketing status bar (9:41, full battery/signal).
xcrun simctl status_bar "$SIM_NAME" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 2>/dev/null || true

# Mic permission for the Voice screen (no-op until the app is installed once;
# the UI test's interruption monitor covers the speech-recognition alert).
xcrun simctl privacy "$SIM_NAME" grant microphone "$BUNDLE_ID" 2>/dev/null || true

mkdir -p "$OUT_ROOT" "$RESULTS_ROOT"
failures=()

for entry in "${LOCALES[@]}"; do
  IFS='|' read -r asc_locale app_lang apple_locale currency <<< "$entry"
  if [[ -n "${ONLY:-}" && "$ONLY" != "$asc_locale" ]]; then continue; fi

  echo ""
  echo "━━━ $asc_locale  (lang=$app_lang locale=$apple_locale currency=$currency) ━━━"
  result_bundle="$RESULTS_ROOT/$asc_locale.xcresult"
  rm -rf "$result_bundle"

  TEST_RUNNER_SCREENSHOT_LANGUAGE="$app_lang" \
  TEST_RUNNER_SCREENSHOT_LOCALE="$apple_locale" \
  TEST_RUNNER_SCREENSHOT_DEMO_CURRENCY="$currency" \
  xcodebuild test \
    -scheme Tenra \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -only-testing:TenraUITests/ScreenshotCaptureTests \
    -parallel-testing-enabled NO \
    -resultBundlePath "$result_bundle" \
    2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)|error:" | head -20

  # Export attachments (PNG screenshots) from the result bundle.
  dest="$OUT_ROOT/$asc_locale"
  rm -rf "$dest"
  mkdir -p "$dest"
  export_dir="$(mktemp -d)"
  if xcrun xcresulttool export attachments --path "$result_bundle" --output-path "$export_dir" >/dev/null 2>&1; then
    python3 - "$export_dir" "$dest" <<'PY'
import json, shutil, sys, os, re
export_dir, dest = sys.argv[1], sys.argv[2]
manifest_path = os.path.join(export_dir, "manifest.json")
count = 0
if os.path.exists(manifest_path):
    with open(manifest_path) as f:
        manifest = json.load(f)
    entries = manifest if isinstance(manifest, list) else manifest.get("testPlans", manifest)
    def walk(node):
        global count
        if isinstance(node, dict):
            atts = node.get("attachments")
            if isinstance(atts, list):
                for att in atts:
                    exported = att.get("exportedFileName") or att.get("exportedFileID")
                    human = att.get("suggestedHumanReadableName") or exported
                    if not exported:
                        continue
                    src = os.path.join(export_dir, exported)
                    if not os.path.exists(src):
                        continue
                    base = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.splitext(human)[0])
                    # Only our named marketing captures ("01-home"…"08-multicurrency") —
                    # skip auto-attachments (failure recordings, synthesized events).
                    m = re.match(r"^(0[1-8]-[a-z-]+)", base)
                    if not m:
                        continue
                    shutil.copy(src, os.path.join(dest, m.group(1) + ".png"))
                    count += 1
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(entries)
else:
    for name in os.listdir(export_dir):
        if name.lower().endswith(".png"):
            shutil.copy(os.path.join(export_dir, name), os.path.join(dest, name))
            count += 1
print(f"  exported {count} screenshots -> {dest}")
PY
  else
    echo "  ⚠️ attachment export failed for $asc_locale"
    failures+=("$asc_locale")
  fi
  rm -rf "$export_dir"

  shots=$(ls "$dest" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$shots" -lt 8 ]]; then
    echo "  ⚠️ $asc_locale: only $shots screenshots (expected 8)"
    failures+=("$asc_locale")
  else
    echo "  ✅ $asc_locale: $shots screenshots"
  fi
done

echo ""
if (( ${#failures[@]} > 0 )); then
  echo "⚠️ Locales with problems: ${failures[*]}"
  exit 1
fi
echo "✅ All locales captured into $OUT_ROOT/"
