#!/usr/bin/env bash
# End-to-end checks on an emulator (doc/TESTING.md §4).
#
# Drives the example app with adb: taps buttons found in the UI hierarchy,
# sends SMS and reads the results the app prints. Needs one connected device
# with Google Play services (or set ANDROID_SERIAL), adb and python3.
#
# On an emulator the SMS goes through the emulator console. On a real device
# the script prints each SMS and waits until you have sent it from another
# phone and it has arrived; run it in a terminal for that.
#
#   tool/e2e.sh                 # build the release (R8) example, run all
#   tool/e2e.sh --no-build m05  # reuse the last build, run one scenario
#
# The SMS bodies are test fixtures; the sender is a reserved demo number.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=com.emirkanacar.sms_consent_kit_example
APK="$ROOT/example/build/app/outputs/flutter-apk/app-release.apk"
SENDER=5550100
WORK="$(mktemp -d)"
trap 'restore_settings; rm -rf "$WORK"' EXIT

build=1
selected=()
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    *) selected+=("$arg") ;;
  esac
done

# region UI helpers

dump() {
  adb shell uiautomator dump /sdcard/sck_ui.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/sck_ui.xml >"$WORK/ui.xml" 2>/dev/null || true
}

# Prints "x y" of the node whose text, content-desc or resource-id equals
# $1, else the first one containing it.
find_node() {
  python3 -I - "$WORK/ui.xml" "$1" <<'PY'
import re, sys, xml.etree.ElementTree as ET
try:
    nodes = list(ET.parse(sys.argv[1]).iter('node'))
except ET.ParseError:
    sys.exit(0)
want = sys.argv[2].lower()
def labels(n):
    return [(n.get(k) or '').lower() for k in ('text', 'content-desc', 'resource-id')]
hit = next((n for n in nodes if want in labels(n)), None)
if hit is None:
    hit = next((n for n in nodes if any(want in l for l in labels(n))), None)
if hit is not None:
    a, b, c, d = map(int, re.findall(r'\d+', hit.get('bounds')))
    print((a + c) // 2, (b + d) // 2)
PY
}

screen_text() {
  python3 -I - "$WORK/ui.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    for n in ET.parse(sys.argv[1]).iter('node'):
        for k in ('text', 'content-desc'):
            if n.get(k):
                print(n.get(k))
except ET.ParseError:
    pass
PY
}

# wait_for TEXT [SECONDS]: polls the screen until TEXT appears.
wait_for() {
  local deadline=$((SECONDS + ${2:-15}))
  while ((SECONDS < deadline)); do
    dump
    if screen_text | grep -qF -- "$1" || grep -qF -- "resource-id=\"$1\"" "$WORK/ui.xml"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

tap() {
  local xy
  wait_for "$1" "${2:-15}" || true
  xy="$(find_node "$1")"
  [[ -n "$xy" ]] || fail "button not found: $1"
  # shellcheck disable=SC2086
  adb shell input tap $xy
}

ALLOW=com.google.android.gms:id/positive_button
DENY=com.google.android.gms:id/negative_button

sheet_visible() {
  dump
  grep -q "$ALLOW" "$WORK/ui.xml"
}

wait_sheet() {
  local deadline=$((SECONDS + ${1:-20}))
  while ((SECONDS < deadline)); do
    sheet_visible && return 0
    sleep 1
  done
  return 1
}

# Asserts that no consent sheet shows up for $1 seconds.
expect_no_sheet() {
  local deadline=$((SECONDS + ${1:-10}))
  while ((SECONDS < deadline)); do
    sheet_visible && fail "a consent sheet appeared"
    sleep 1
  done
}

is_emulator() { [[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" == 1 ]]; }

# sms BODY [HINT]: sends BODY to the device. On a real device asks you to.
sms() {
  if ((emulator)); then
    adb emu sms send "$SENDER" "$1" >/dev/null
    return
  fi
  echo "    >>> From another phone${2:+ ($2)}, send this SMS to the device:"
  echo "    >>>   $1"
  read -r -p "    >>> Press Enter once it has arrived on the device. " _ </dev/tty
}
back() { adb shell input keyevent KEYCODE_BACK; }
home() { adb shell input keyevent KEYCODE_HOME; }
foreground() { adb shell am start -n "$APP/.MainActivity" >/dev/null; }

launch() {
  adb shell am force-stop "$APP"
  adb shell am start -W -n "$APP/.MainActivity" >/dev/null
  wait_for "Support: " 20 || fail "app did not start"
}

expect_text() { wait_for "$1" "${2:-15}" || fail "expected on screen: $1"; }

app_alive() { [[ -n "$(adb shell pidof "$APP" | tr -d '\r')" ]]; }

# The device's own values, restored on exit (it may be your phone).
saved_settings=()
save_settings() {
  local key value
  for key in "global always_finish_activities" "system accelerometer_rotation" "system user_rotation"; do
    # shellcheck disable=SC2086
    value="$(adb shell settings get $key | tr -d '\r')"
    saved_settings+=("$key $value")
  done
}

restore_settings() {
  local entry
  for entry in ${saved_settings[@]+"${saved_settings[@]}"}; do
    set -- $entry
    if [[ "$3" == null ]]; then
      adb shell settings delete "$1" "$2" >/dev/null 2>&1 || true
    else
      adb shell settings put "$1" "$2" "$3" >/dev/null 2>&1 || true
    fi
  done
}

# endregion

failed=0
current=""
fail() {
  echo "  FAIL ($current): $*" >&2
  dump
  screen_text | sed 's/^/    | /' >&2
  exit 1
}

# region Scenarios

CODE_SMS="Your code is 482913. Do not share it."

m12_received() {
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  wait_sheet || fail "no consent sheet"
  tap "$ALLOW"
  expect_text "Received: code=482913"
}

m05_denied() {
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  wait_sheet || fail "no consent sheet"
  tap "$DENY"
  expect_text "Result: SmsConsentDenied()"
}

m02_rotate_while_sheet_open() {
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  wait_sheet || fail "no consent sheet"
  adb shell settings put system accelerometer_rotation 0
  adb shell settings put system user_rotation 1
  sleep 3
  wait_sheet 10 || fail "sheet lost after rotation"
  tap "$ALLOW"
  expect_text "Received: code=482913"
  adb shell settings put system user_rotation 0
}

m03_background_then_return() {
  launch
  tap "Request code"
  sleep 1
  home
  sleep 1
  sms "$CODE_SMS"
  sleep 5
  foreground
  wait_sheet || fail "the sheet did not open on return"
  tap "$ALLOW"
  expect_text "Received: code=482913"
}

m04_background_too_long() {
  launch
  tap "Request code"
  sleep 1
  home
  sleep 1
  sms "$CODE_SMS"
  sleep 35 # maxDelay is 30 s
  foreground
  expect_text "Result: SmsConsentTimedOut()"
  expect_no_sheet 5
}

m01_leave_otp_screen() {
  launch
  tap "OTP page"
  expect_text "Listening"
  back
  expect_text "Request code"
  sleep 1
  sms "$CODE_SMS"
  expect_no_sheet 10
}

m01_covered_otp_screen() {
  launch
  tap "OTP page"
  expect_text "Listening"
  tap "Open help"
  expect_text "Listening stopped"
  sleep 1
  sms "$CODE_SMS"
  expect_no_sheet 10
  back
  expect_text "SmsConsentCancelled(routeHidden)"
}

otp_scope_fills_field() {
  launch
  tap "OTP page"
  expect_text "Listening"
  sleep 1
  sms "$CODE_SMS"
  wait_sheet || fail "no consent sheet"
  tap "$ALLOW"
  expect_text "482913"
  expect_text "SmsConsentReceived(message: <redacted"
}

m09_two_sms() {
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  sms "Your code is 777111." "right after the first one"
  wait_sheet || fail "no consent sheet"
  dump
  screen_text | grep -qF "482913" || fail "the sheet is not for the first SMS"
  tap "$ALLOW"
  expect_text "Received: code=482913"
  expect_no_sheet 8
}

m10_dont_keep_activities() {
  adb shell settings put global always_finish_activities 1
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  wait_sheet || fail "no consent sheet"
  tap "$ALLOW"
  sleep 3
  app_alive || fail "the app process died"
  # Either the result arrives or it is dropped (EC-05); never a crash.
  wait_for "Request code" 10 || fail "the app did not come back"
  adb shell settings put global always_finish_activities 0
}

m13_old_sms_new_session() {
  launch
  tap "OTP page"
  expect_text "Listening"
  back
  expect_text "Request code"
  tap "Request code"
  sleep 1
  sms "$CODE_SMS"
  # EC-02: an SMS cannot be tied to the screen that asked for it; the new
  # session gets it. Recorded, not a failure.
  if wait_sheet; then
    tap "$ALLOW"
    expect_text "Received: code=482913"
    echo "    recorded: the new session received the SMS (EC-02)"
  else
    echo "    recorded: no sheet"
  fi
}

# Real devices only: the emulator console cannot send from a contact.
m08_sender_in_contacts() {
  ((emulator)) && { echo "    skipped: needs a real device"; return 0; }
  launch
  tap "Request code"
  sleep 1
  sms "$CODE_SMS" "from a number saved in this device's contacts"
  expect_no_sheet 15
  echo "    waiting for the 2 minute timeout"
  expect_text "Result: SmsConsentTimedOut()" 130
}

ALL=(
  m12_received
  m05_denied
  m02_rotate_while_sheet_open
  m03_background_then_return
  m04_background_too_long
  m01_leave_otp_screen
  m01_covered_otp_screen
  otp_scope_fills_field
  m09_two_sms
  m10_dont_keep_activities
  m13_old_sms_new_session
  m08_sender_in_contacts
)

# endregion

if [[ -z "${ANDROID_SERIAL:-}" ]] && [[ "$(adb devices | grep -c $'\tdevice$')" != 1 ]]; then
  echo "Connect exactly one device, or set ANDROID_SERIAL." >&2
  exit 2
fi
emulator=0
is_emulator && emulator=1
echo "Device: $(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r')"

if ((build)); then
  (cd "$ROOT/example" && flutter build apk --release)
fi
adb install -r "$APK" >/dev/null
save_settings

run=()
if ((${#selected[@]})); then
  for want in "${selected[@]}"; do
    for name in "${ALL[@]}"; do [[ "$name" == "$want"* ]] && run+=("$name"); done
  done
else
  run=("${ALL[@]}")
fi

for name in "${run[@]}"; do
  current="$name"
  echo "- $name"
  if (set -e; "$name"); then
    echo "  ok"
  else
    failed=$((failed + 1))
  fi
done
adb shell am force-stop "$APP"

echo
if ((failed)); then
  echo "$failed of ${#run[@]} scenarios failed."
  exit 1
fi
echo "All ${#run[@]} scenarios passed."
