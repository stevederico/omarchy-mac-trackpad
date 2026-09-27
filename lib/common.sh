# shellcheck shell=bash
# Shared helpers for install.sh and uninstall.sh. Sourced, never executed.
#
# Both scripts work in two passes over the same steps: a "plan" pass that
# only prints what would change, then an "apply" pass that does it.

NAME="omarchy-mac-trackpad"
MARK_BEGIN=">>> $NAME >>>"
MARK_END="<<< $NAME <<<"
# shellcheck disable=SC2034  # used by uninstall.sh
OWNED_TAG="Installed by $NAME"

# Test hook: a fake filesystem root for the /etc files. When set, nothing
# uses sudo and udev is never reloaded.
ROOT="${MAC_TRACKPAD_ROOT:-}"

# Omarchy's Hyprland bootstrap loads user modules from $HOME/.config.
HYPR_DIR="$HOME/.config/hypr"
# shellcheck disable=SC2034
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
# shellcheck disable=SC2034
HYPR_SNIPPET="$HYPR_DIR/mac-trackpad.lua"
# shellcheck disable=SC2034
HYPR_OPTIONAL="$HYPR_DIR/mac-trackpad-optional.lua"

# shellcheck disable=SC2034
QUIRKS_DST="$ROOT/etc/libinput/local-overrides.quirks"
# shellcheck disable=SC2034
HWDB_DST="$ROOT/etc/udev/hwdb.d/71-apple-t2-trackpad.hwdb"
# shellcheck disable=SC2034
RULES_DST="$ROOT/etc/udev/rules.d/71-apple-t2-trackpad.rules"

BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME/backups/$(date +%Y%m%d-%H%M%S)"

# shellcheck disable=SC2034
DRY_RUN=0
ASSUME_YES=0
# shellcheck disable=SC2034
DO_HYPR=1
# shellcheck disable=SC2034
DO_SYSTEM=1

MODE=plan
CHANGED=0
SYSTEM_CHANGED=0
BACKED_UP=0
STAGE=""

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

init() {
  local cmd
  for cmd in awk cmp cp diff grep install mktemp rm sed; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
  if [[ $EUID -eq 0 && -z $ROOT ]]; then
    die "run this as your own user. sudo is called only for the /etc files."
  fi
  STAGE=$(mktemp -d)
  trap 'rm -rf "$STAGE"' EXIT
}

# Run a command with root rights. Only ever used for paths under /etc.
as_root() {
  if [[ -n $ROOT || $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

backup() {
  local src=$1 dst
  [[ -e $src ]] || return 0
  dst="$BACKUP_DIR$src"
  mkdir -p "$(dirname "$dst")"
  cp -pL "$src" "$dst"
  BACKED_UP=1
  say "  backup     $dst"
}

show_diff() {
  local old=$1 new=$2
  [[ -e $old ]] || old=/dev/null
  diff -u --label "$1 (now)" --label "$1 (after)" "$old" "$new" | sed 's/^/      /' || true
}

mark_changed() {
  # shellcheck disable=SC2034  # read by install.sh and uninstall.sh
  CHANGED=1
  if [[ $1 == root ]]; then
    SYSTEM_CHANGED=1
  fi
}

# write_file <staged file> <destination> <user|root>
write_file() {
  local staged=$1 dst=$2 owner=$3
  if [[ -f $dst ]] && cmp -s "$staged" "$dst"; then
    if [[ $MODE == plan ]]; then
      say "  unchanged  $dst"
    fi
    return 0
  fi
  mark_changed "$owner"
  if [[ $MODE == plan ]]; then
    if [[ -e $dst ]]; then
      say "  update     $dst"
    else
      say "  create     $dst"
    fi
    show_diff "$dst" "$staged"
    return 0
  fi
  backup "$dst"
  if [[ $owner == root ]]; then
    as_root install -D -m 0644 "$staged" "$dst"
  elif [[ -e $dst ]]; then
    # Write through symlinks (stow setups) and keep the file's mode.
    cat "$staged" >"$dst"
  else
    install -D -m 0644 "$staged" "$dst"
  fi
  say "  wrote      $dst"
}

# remove_file <destination> <user|root>
remove_file() {
  local dst=$1 owner=$2
  if [[ ! -e $dst && ! -L $dst ]]; then
    if [[ $MODE == plan ]]; then
      say "  absent     $dst"
    fi
    return 0
  fi
  mark_changed "$owner"
  if [[ $MODE == plan ]]; then
    say "  remove     $dst"
    return 0
  fi
  backup "$dst"
  if [[ $owner == root ]]; then
    as_root rm -f "$dst"
  else
    rm -f "$dst"
  fi
  say "  removed    $dst"
}

# Print a file without the block this tool manages.
strip_block() {
  [[ -f $1 ]] || return 0
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) { skip = 1; next }
    index($0, e) { skip = 0; next }
    !skip { print }
  ' "$1"
}

has_block() {
  [[ -f $1 ]] && grep -qF "$MARK_BEGIN" "$1"
}

has_content() {
  [[ -f $1 ]] && grep -q '[^[:space:]]' "$1"
}

confirm() {
  local reply
  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi
  [[ -t 0 ]] || die "not a terminal. Re-run with --yes to apply, or --dry-run to preview."
  read -r -p "Apply these changes? [y/N] " reply
  [[ $reply =~ ^[Yy]$ ]]
}

sudo_notice() {
  if [[ $SYSTEM_CHANGED -eq 1 && -z $ROOT && $EUID -ne 0 ]]; then
    say "sudo is used for the /etc files only. You may be asked for your password."
  fi
}

reload_udev() {
  if [[ -n $ROOT ]]; then
    say "  skipped    udev reload (test root)"
    return 0
  fi
  as_root systemd-hwdb update
  as_root udevadm control --reload
  say "  reloaded   udev hwdb and rules"
}

backup_notice() {
  if [[ $BACKED_UP -eq 1 ]]; then
    say "Backups: $BACKUP_DIR"
  fi
}
