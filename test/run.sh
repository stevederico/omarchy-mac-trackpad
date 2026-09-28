#!/usr/bin/env bash
# End-to-end test for install.sh and uninstall.sh.
#
# Runs both scripts for real, but only against a throwaway HOME and a fake
# /etc root (MAC_TRACKPAD_ROOT). Never writes to the live system, never runs
# the real sudo, never reloads udev. The sudo failure test uses a fake sudo.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export MAC_TRACKPAD_ROOT="$SANDBOX/root"
unset XDG_STATE_HOME

HYPR="$HOME/.config/hypr"
ETC="$MAC_TRACKPAD_ROOT/etc"
BACKUPS="$HOME/.local/state/omarchy-mac-trackpad/backups"
MBP=(--model "MacBookPro16,1" --usb-id 0340)

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok: %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$name"
  else
    fail "$name"
  fi
}

check_not() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name"
  else
    ok "$name"
  fi
}

reset() {
  rm -rf "$HOME" "$MAC_TRACKPAD_ROOT"
  mkdir -p "$HYPR" "$MAC_TRACKPAD_ROOT"
  printf '%s\n' '-- user config' 'require("hypr.input")' >"$HYPR/hyprland.lua"
  cp "$HYPR/hyprland.lua" "$SANDBOX/hyprland.orig"
}

install() { "$REPO/install.sh" "$@" </dev/null; }
uninstall() { "$REPO/uninstall.sh" "$@" </dev/null; }

count_backups() {
  if [[ -d $BACKUPS ]]; then
    find "$BACKUPS" -type f | wc -l
  else
    echo 0
  fi
}

echo "== dry run changes nothing"
reset
install --dry-run "${MBP[@]}" >"$SANDBOX/out"
check "dry run prints a plan" grep -q "create .*mac-trackpad.lua" "$SANDBOX/out"
check "dry run says nothing changed" grep -q "Nothing was changed" "$SANDBOX/out"
check "dry run leaves hyprland.lua alone" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.orig"
check_not "dry run creates no snippet" test -e "$HYPR/mac-trackpad.lua"
check_not "dry run creates no /etc" test -e "$ETC"
check_not "dry run creates no backups" test -e "$BACKUPS"

echo "== no terminal and no --yes aborts"
reset
check_not "install without --yes fails off a terminal" install "${MBP[@]}"
check "abort leaves hyprland.lua alone" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.orig"
check_not "abort creates no /etc" test -e "$ETC"

echo "== install"
reset
install --yes "${MBP[@]}" >"$SANDBOX/out"
check "snippet installed" cmp -s "$REPO/hypr/mac-trackpad.lua" "$HYPR/mac-trackpad.lua"
check_not "optional not installed by default" test -e "$HYPR/mac-trackpad-optional.lua"
check "hyprland.lua requires the snippet" grep -qF 'require("hypr.mac-trackpad")' "$HYPR/hyprland.lua"
check_not "hyprland.lua does not require optional" grep -qF 'mac-trackpad-optional' "$HYPR/hyprland.lua"
check "hyprland.lua keeps user lines" grep -qF 'require("hypr.input")' "$HYPR/hyprland.lua"
check "hyprland.lua backed up" test "$(count_backups)" -eq 1
check "quirks section installed" grep -qF '[MacBookPro16,1 T2 Trackpad]' "$ETC/libinput/local-overrides.quirks"
check "quirks keep size hint on tested model" grep -q '^AttrSizeHint=160x100' "$ETC/libinput/local-overrides.quirks"
check "hwdb installed as shipped" cmp -s "$REPO/etc/udev/hwdb.d/71-apple-t2-trackpad.hwdb" "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
check "rules installed as shipped" cmp -s "$REPO/etc/udev/rules.d/71-apple-t2-trackpad.rules" "$ETC/udev/rules.d/71-apple-t2-trackpad.rules"
check "udev reload skipped in test root" grep -q "skipped .*udev reload" "$SANDBOX/out"

echo "== install is idempotent"
cp "$HYPR/hyprland.lua" "$SANDBOX/hyprland.installed"
cp "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.installed"
before=$(count_backups)
install --yes "${MBP[@]}" >"$SANDBOX/out"
check "second run reports nothing to do" grep -q "Already installed" "$SANDBOX/out"
check "second run leaves hyprland.lua alone" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.installed"
check "second run leaves quirks alone" cmp -s "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.installed"
check "second run makes no backups" test "$(count_backups)" -eq "$before"
check "one block in hyprland.lua" test "$(grep -c '>>> omarchy-mac-trackpad >>>' "$HYPR/hyprland.lua")" -eq 1
check "one block in quirks" test "$(grep -c '>>> omarchy-mac-trackpad >>>' "$ETC/libinput/local-overrides.quirks")" -eq 1

echo "== optional values"
install --yes --with-optional "${MBP[@]}" >/dev/null
check "optional installed" cmp -s "$REPO/hypr/mac-trackpad-optional.lua" "$HYPR/mac-trackpad-optional.lua"
check "hyprland.lua requires optional" grep -qF 'require("hypr.mac-trackpad-optional")' "$HYPR/hyprland.lua"
install --yes "${MBP[@]}" >/dev/null
check_not "optional removed when flag dropped" test -e "$HYPR/mac-trackpad-optional.lua"
check "hyprland.lua back to the plain install" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.installed"

echo "== uninstall"
uninstall --dry-run >"$SANDBOX/out"
check "uninstall dry run keeps the snippet" test -e "$HYPR/mac-trackpad.lua"
uninstall --yes >/dev/null
check "hyprland.lua restored byte for byte" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.orig"
check_not "snippet removed" test -e "$HYPR/mac-trackpad.lua"
check_not "quirks file removed when only ours" test -e "$ETC/libinput/local-overrides.quirks"
check_not "hwdb removed" test -e "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
check_not "rules removed" test -e "$ETC/udev/rules.d/71-apple-t2-trackpad.rules"
uninstall --yes >"$SANDBOX/out"
check "second uninstall reports nothing to do" grep -q "Nothing to do" "$SANDBOX/out"

echo "== hyprland.lua is never deleted"
reset
: >"$HYPR/hyprland.lua"
install --yes --hypr-only >/dev/null
check "empty hyprland.lua gets the block" grep -qF 'require("hypr.mac-trackpad")' "$HYPR/hyprland.lua"
uninstall --yes --hypr-only >/dev/null
check "hyprland.lua kept after uninstall" test -f "$HYPR/hyprland.lua"
check "hyprland.lua back to empty" test ! -s "$HYPR/hyprland.lua"

echo "== missing final newline"
reset
printf '%s\n%s' '-- user config' 'require("hypr.input")' >"$HYPR/hyprland.lua"
cp "$HYPR/hyprland.lua" "$SANDBOX/hyprland.noeol"
mkdir -p "$ETC/libinput"
printf '%s\n%s' '[Other Mouse]' 'MatchName=*Some Mouse*' >"$ETC/libinput/local-overrides.quirks"
cp "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.noeol"
install --yes "${MBP[@]}" >/dev/null
check "last user line stays whole" grep -qxF 'require("hypr.input")' "$HYPR/hyprland.lua"
check "block starts on its own line" grep -qx -- '-- >>> omarchy-mac-trackpad >>>.*' "$HYPR/hyprland.lua"
check "last quirks line stays whole" grep -qxF 'MatchName=*Some Mouse*' "$ETC/libinput/local-overrides.quirks"
cp "$HYPR/hyprland.lua" "$SANDBOX/hyprland.installed"
install --yes "${MBP[@]}" >"$SANDBOX/out"
check "no-newline install is idempotent" grep -q "Already installed" "$SANDBOX/out"
check "no-newline second run leaves hyprland.lua alone" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.installed"
uninstall --yes >/dev/null
check "no-newline hyprland.lua restored byte for byte" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.noeol"
check "no-newline quirks restored byte for byte" cmp -s "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.noeol"

echo "== lines added after the block"
install --yes --hypr-only >/dev/null
printf '%s\n' '-- added later' >>"$HYPR/hyprland.lua"
uninstall --yes --hypr-only >/dev/null
printf '%s\n%s\n%s\n' '-- user config' 'require("hypr.input")' '-- added later' >"$SANDBOX/hyprland.later"
check "later lines kept, each on its own line" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.later"

echo "== existing files are kept"
reset
mkdir -p "$ETC/libinput" "$ETC/udev/rules.d"
printf '%s\n' '[Other Mouse]' 'MatchName=*Some Mouse*' 'AttrEventCode=-BTN_SIDE' >"$ETC/libinput/local-overrides.quirks"
cp "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.orig"
printf '%s\n' '# hand written' >"$ETC/udev/rules.d/71-apple-t2-trackpad.rules"
install --yes "${MBP[@]}" >/dev/null
check "quirks keep the other section" grep -qF '[Other Mouse]' "$ETC/libinput/local-overrides.quirks"
check "quirks gain our section" grep -qF '[MacBookPro16,1 T2 Trackpad]' "$ETC/libinput/local-overrides.quirks"
check "replaced rules file was backed up" test -n "$(find "$BACKUPS" -name '71-apple-t2-trackpad.rules' -print -quit)"
uninstall --yes >/dev/null
check "quirks restored byte for byte" cmp -s "$ETC/libinput/local-overrides.quirks" "$SANDBOX/quirks.orig"

echo "== uninstall leaves udev files it did not install"
reset
mkdir -p "$ETC/udev/hwdb.d"
printf '%s\n' '# hand written' >"$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
uninstall --yes >"$SANDBOX/out"
check "foreign hwdb kept" test -e "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
uninstall --yes --force >/dev/null
check_not "foreign hwdb removed with --force" test -e "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"

echo "== symlinked hyprland.lua (stow)"
reset
mkdir -p "$SANDBOX/dotfiles"
mv "$HYPR/hyprland.lua" "$SANDBOX/dotfiles/hyprland.lua"
ln -s "$SANDBOX/dotfiles/hyprland.lua" "$HYPR/hyprland.lua"
install --yes --hypr-only >/dev/null
check "hyprland.lua is still a symlink" test -L "$HYPR/hyprland.lua"
check "symlink target got the block" grep -qF 'require("hypr.mac-trackpad")' "$SANDBOX/dotfiles/hyprland.lua"
check_not "--hypr-only creates no /etc" test -e "$ETC"
uninstall --yes --hypr-only >/dev/null
check "symlink target restored" cmp -s "$SANDBOX/dotfiles/hyprland.lua" "$SANDBOX/hyprland.orig"

echo "== other models"
reset
check_not "untested T2 model needs --force" install --yes --model MacBookPro15,1
check_not "refusal creates no /etc" test -e "$ETC"
install --yes --force --model MacBookPro15,1 >/dev/null 2>&1
check "quirks match the forced model" grep -qF 'pnMacBookPro15,1*' "$ETC/libinput/local-overrides.quirks"
check_not "quirks drop the 16-inch size hint" grep -q '^AttrSizeHint=' "$ETC/libinput/local-overrides.quirks"
check "quirks say untested" grep -q 'Untested on this model' "$ETC/libinput/local-overrides.quirks"
check "hwdb uses the model's usb id" grep -qF 'touchpad:usb:v05acp027c:*' "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
check "rules use the model's usb id" grep -qF 'ENV{ID_MODEL_ID}=="027c"' "$ETC/udev/rules.d/71-apple-t2-trackpad.rules"
check_not "no tested id left behind" grep -rq '0340' "$ETC"

reset
install --yes --force --model "MacBookPro15,1" --usb-id 0278 >/dev/null 2>&1
check "alt MacBookPro15,1 id 0278 accepted" grep -qF 'touchpad:usb:v05acp0278:*' "$ETC/udev/hwdb.d/71-apple-t2-trackpad.hwdb"

reset
check_not "non-T2 MacBook refuses even with --force" install --yes --force --model "MacBookPro11,2" --usb-id 0262
install --yes --model "MacBookPro11,2" --usb-id 0262 >/dev/null 2>"$SANDBOX/err" || true
check "non-T2 refusal names the id" grep -q "not a known T2 trackpad id" "$SANDBOX/err"
check_not "non-T2 refusal does not offer --force" grep -q -- "--force" "$SANDBOX/err"
check_not "non-T2 refusal creates no /etc" test -e "$ETC"

reset
check_not "non-MacBook refuses the /etc part" install --yes --force --model "OptiPlex 7050"
check_not "non-MacBook refusal creates no /etc" test -e "$ETC"
check "non-MacBook can use --hypr-only" install --yes --hypr-only --model "OptiPlex 7050"

echo "== missing Hyprland Lua config"
reset
rm "$HYPR/hyprland.lua"
check_not "install fails without hyprland.lua" install --yes "${MBP[@]}"
check_not "failure creates no /etc" test -e "$ETC"
check "--system-only works without hyprland.lua" install --yes --system-only "${MBP[@]}"

echo "== failed sudo changes nothing"
# Real paths, no fake root, but a fake sudo that refuses. Nothing can be
# written to /etc as a normal user, and the fake sudo does nothing.
if [[ $EUID -eq 0 ]]; then
  echo "note: skipped, needs a normal user"
else
  reset
  mkdir -p "$SANDBOX/bin"
  # shellcheck disable=SC2016  # expands when the fake sudo runs
  printf '%s\n' '#!/bin/sh' 'echo "$*" >>"$SUDO_LOG"' 'exit 1' >"$SANDBOX/bin/sudo"
  chmod +x "$SANDBOX/bin/sudo"
  export SUDO_LOG="$SANDBOX/sudo.log"
  : >"$SUDO_LOG"
  check_not "install stops when sudo fails" env -u MAC_TRACKPAD_ROOT PATH="$SANDBOX/bin:$PATH" "$REPO/install.sh" --yes "${MBP[@]}"
  check "only sudo -v was tried" test "$(cat "$SUDO_LOG")" = "-v"
  check "hyprland.lua untouched after sudo failure" cmp -s "$HYPR/hyprland.lua" "$SANDBOX/hyprland.orig"
  check_not "no snippet after sudo failure" test -e "$HYPR/mac-trackpad.lua"
  check_not "no backups after sudo failure" test -e "$BACKUPS"
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
