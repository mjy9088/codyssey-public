#!/usr/bin/env bash
set -u
umask 077

uname_bin=${UNAME_BIN:-uname}
defaults_bin=${DEFAULTS_BIN:-defaults}
plistbuddy_bin=${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}
plutil_bin=${PLUTIL_BIN:-plutil}
killall_bin=${KILLALL_BIN:-killall}
applications_dir=${CODYSSEY_APPLICATIONS_DIR:-/Applications}
system_applications_dir=${CODYSSEY_SYSTEM_APPLICATIONS_DIR:-/System/Applications}

[[ $("$uname_bin" -s) == Darwin ]] || {
  printf 'macos-setup.sh only supports macOS.\n' >&2
  exit 1
}

input_switch=${CODYSSEY_INPUT_SWITCH:-control-space}
dock_setup=${CODYSSEY_DOCK_SETUP:-}
case ${1:-} in
  '') ;;
  --input-only|--no-dock|--desktop-only) dock_setup=0 ;;
  --shortcuts-only) input_switch=control-space; dock_setup=0 ;;
  *) printf 'Usage: bash macos-setup.sh [--input-only | --no-dock | --shortcuts-only | --desktop-only]\n' >&2; exit 2 ;;
esac
# Use the controlling terminal so curl | sh does not consume installer text.
if [[ -t 1 ]] && { true </dev/tty && true >/dev/tty; } 2>/dev/null; then
  if [[ -z $dock_setup ]]; then
    printf 'Pin Terminal, Chrome and the j terminal launcher in the Dock, and remove stacks/recent apps? [y/N] ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=n
    case $answer in y|Y|yes|YES) dock_setup=1 ;; *) dock_setup=0 ;; esac
  fi
fi
input_switch=${input_switch:-control-space}
dock_setup=${dock_setup:-${CODYSSEY_MACOS_SETUP:-0}}
case $input_switch in control-space|caps-lock) ;; *) printf 'CODYSSEY_INPUT_SWITCH must be control-space or caps-lock.\n' >&2; exit 2 ;; esac
case $dock_setup in 0|1) ;; *) printf 'CODYSSEY_DOCK_SETUP must be 0 or 1.\n' >&2; exit 2 ;; esac
if [[ $input_switch == caps-lock ]]; then
  # Gureum 1.13.2 lacks TICapsLockLanguageSwitchCapable metadata (upstream #918).
  # The native Apple source also failed to produce Hangul in this classroom
  # session. A saved Caps Lock preference therefore cannot establish usability.
  # Keep the confirmed Control-Space path; never swap input methods as a fallback.
  printf 'Caps Lock switching is not working reliably in the reference environment. Choose Control-Space. No automatic input-method replacement will be performed.\n' >&2
  exit 1
fi

backup_parent="$HOME/Library/Application Support/codyssey-init/macos-backups"
mkdir -p "$backup_parent" || exit 0
chmod 0700 "$backup_parent" || exit 0
backup_root=$(mktemp -d "$backup_parent/run.XXXXXX") || exit 0
chmod 0700 "$backup_root"

warn() {
  printf 'macOS preference group skipped: %s\n' "$1" >&2
}

domain_exists() {
  local wanted=$1 listed domain
  listed=$("$defaults_bin" domains 2>/dev/null) || return 2
  while IFS= read -r domain; do
    domain=${domain#"${domain%%[![:space:]]*}"}
    domain=${domain%"${domain##*[![:space:]]}"}
    [[ $domain == "$wanted" ]] && return 0
  done < <(printf '%s\n' "$listed" | tr ',' '\n')
  return 1
}

backup_domain() {
  local group=$1 domain=$2 target domain_status
  target="$backup_root/$group.plist"
  if "$defaults_bin" export "$domain" "$target" >/dev/null 2>&1; then
    chmod 0600 "$target"
    BACKUP_KIND=present
    BACKUP_PATH=$target
    return 0
  fi
  rm -f "$target"
  if [[ $domain != NSGlobalDomain ]]; then
    domain_exists "$domain"
    domain_status=$?
    if [[ $domain_status -eq 1 ]]; then
      BACKUP_KIND=absent
      BACKUP_PATH="$backup_root/$group.missing"
      : >"$BACKUP_PATH"
      chmod 0600 "$BACKUP_PATH"
      return 0
    fi
  fi
  BACKUP_KIND=unreadable
  BACKUP_PATH=
  warn "$group backup could not be read"
  return 1
}

restore_domain() {
  local domain=$1
  if [[ $BACKUP_KIND == present ]]; then
    "$defaults_bin" import "$domain" "$BACKUP_PATH" >/dev/null 2>&1
  else
    "$defaults_bin" delete "$domain" >/dev/null 2>&1
  fi
}

apply_text() {
  local key failed=0
  backup_domain text NSGlobalDomain || return
  for key in \
    NSAutomaticCapitalizationEnabled NSAutomaticPeriodSubstitutionEnabled \
    NSAutomaticSpellingCorrectionEnabled WebAutomaticSpellingCorrectionEnabled \
    NSAutomaticInlinePredictionEnabled NSAutomaticTextCompletionEnabled \
    NSAutomaticQuoteSubstitutionEnabled NSAutomaticDashSubstitutionEnabled \
    NSAutomaticTextReplacementEnabled; do
    "$defaults_bin" write NSGlobalDomain "$key" -bool false >/dev/null 2>&1 || failed=1
  done
  if [[ $failed -eq 1 ]]; then
    restore_domain NSGlobalDomain || warn 'text rollback failed; backup retained'
    warn 'text write failed'
  fi
}

file_url() {
  local LC_ALL=C path=$1 character encoded index
  printf 'file://'
  for ((index=0; index<${#path}; index++)); do
    character=${path:index:1}
    case $character in
      [a-zA-Z0-9/._~-]) printf '%s' "$character" ;;
      *) printf -v encoded '%%%02X' "'$character"; printf '%s' "$encoded" ;;
    esac
  done
}

apply_dock() {
  local terminal_app chrome_app terminal_url chrome_url launcher launcher_url temporary failed=0
  backup_domain dock com.apple.dock || return
  terminal_app="$system_applications_dir/Utilities/Terminal.app"
  chrome_app="$applications_dir/Google Chrome.app"
  [[ -d $chrome_app ]] || chrome_app="$HOME/Applications/Google Chrome.app"
  if [[ ! -d $terminal_app || ! -d $chrome_app ]]; then
    return
  fi
  launcher="$HOME/Library/Application Support/codyssey-init/Codyssey j.command"
  mkdir -p "$(dirname -- "$launcher")" || return 1
  if [[ -e $launcher || -L $launcher ]]; then
    if [[ -L $launcher ]] || ! grep -qx '# codyssey-init: terminal-launcher-v1' "$launcher"; then
      warn 'existing unowned terminal launcher preserved'
      return 1
    fi
  fi
  temporary=$(mktemp "$(dirname -- "$launcher")/.terminal.XXXXXX") || return 1
  {
    printf '%s\n' '#!/bin/zsh' '# codyssey-init: terminal-launcher-v1' 'set -eu' \
      'export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"'
    printf 'cd -- %q\n' "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
    printf '%s\n' 'exec just "$@"'
  } >"$temporary"
  chmod 0700 "$temporary" && mv -f "$temporary" "$launcher" || { rm -f "$temporary"; return 1; }
  launcher_url=$(file_url "$launcher")
  terminal_url=$(file_url "$terminal_app/")
  chrome_url=$(file_url "$chrome_app/")
  "$defaults_bin" write com.apple.dock persistent-apps -array \
    "{tile-data={file-data={_CFURLString=\"$terminal_url\";_CFURLStringType=15;};};tile-type=\"file-tile\";}" \
    "{tile-data={file-data={_CFURLString=\"$chrome_url\";_CFURLStringType=15;};};tile-type=\"file-tile\";}" >/dev/null 2>&1 || failed=1
  "$defaults_bin" write com.apple.dock persistent-others -array \
    "{tile-data={file-data={_CFURLString=\"$launcher_url\";_CFURLStringType=15;};};tile-type=\"file-tile\";}" >/dev/null 2>&1 || failed=1
  "$defaults_bin" write com.apple.dock show-recents -bool false >/dev/null 2>&1 || failed=1
  "$defaults_bin" write com.apple.dock static-only -bool false >/dev/null 2>&1 || failed=1
  if [[ $failed -eq 1 ]]; then
    restore_domain com.apple.dock || warn 'Dock rollback failed; backup retained'
    warn 'Dock write failed'
    return
  fi
  "$killall_bin" -u "${USER:-$(id -un)}" Dock >/dev/null 2>&1 || true
}

apply_input_sources() {
  [[ $input_switch != caps-lock ]] || return 0
  local work index=0 kind bundle mode failed=0
  backup_domain input-sources com.apple.HIToolbox || return
  [[ $BACKUP_KIND == present ]] || { warn 'input source list is unreadable'; return; }
  work=$(mktemp "$backup_root/input-sources.work.XXXXXX") || return
  cp "$BACKUP_PATH" "$work"
  "$plistbuddy_bin" -c 'Print :AppleEnabledInputSources' "$work" >/dev/null 2>&1 || {
    warn 'input source list is unreadable'
    return
  }
  while "$plistbuddy_bin" -c "Print :AppleEnabledInputSources:$index" "$work" >/dev/null 2>&1; do
    kind=$("$plistbuddy_bin" -c "Print :AppleEnabledInputSources:$index:InputSourceKind" "$work" 2>/dev/null || true)
    bundle=$("$plistbuddy_bin" -c "Print :AppleEnabledInputSources:$index:'Bundle ID'" "$work" 2>/dev/null || true)
    mode=$("$plistbuddy_bin" -c "Print :AppleEnabledInputSources:$index:'Input Mode'" "$work" 2>/dev/null || true)
    if [[ $kind == 'Input Mode' && $bundle == 'org.youknowone.inputmethod.Gureum' && $mode == 'org.youknowone.inputmethod.Gureum.han2' ]]; then
      return
    fi
    index=$((index + 1))
  done
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index dict" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:InputSourceKind string 'Input Mode'" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:'Bundle ID' string 'org.youknowone.inputmethod.Gureum'" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:'Input Mode' string 'org.youknowone.inputmethod.Gureum.han2'" "$work" || failed=1
  [[ $failed -eq 0 ]] || { warn 'input source update could not be prepared'; return; }
  if ! "$defaults_bin" import com.apple.HIToolbox "$work" >/dev/null 2>&1; then
    restore_domain com.apple.HIToolbox || warn 'input source rollback failed; backup retained'
    warn 'input source write failed'
  fi
}

add_hotkey() {
  local work=$1 identifier=$2 modifiers=$3
  "$plistbuddy_bin" -c "Delete :AppleSymbolicHotKeys:$identifier" "$work" >/dev/null 2>&1 || true
  "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier dict" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:enabled bool true" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value dict" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:type string standard" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters array" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:0 integer 65535" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:1 integer 49" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:2 integer $modifiers" "$work"
}

apply_hotkeys() {
  local work identifier modifiers
  backup_domain hotkeys com.apple.symbolichotkeys || return 1
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then
    /usr/bin/swift "$(dirname -- "$0")/enable-korean.swift" --shortcuts
    return $?
  fi
  work=$(mktemp "$backup_root/hotkeys.work.XXXXXX") || return 1
  if [[ $BACKUP_KIND == present ]]; then cp "$BACKUP_PATH" "$work"
  else "$plutil_bin" -create xml1 "$work" || return 1; fi
  "$plistbuddy_bin" -c 'Print :AppleSymbolicHotKeys' "$work" >/dev/null 2>&1 ||
    "$plistbuddy_bin" -c 'Add :AppleSymbolicHotKeys dict' "$work" || return 1
  for identifier in 60 61 64 65; do
    case $identifier in 60) modifiers=262144 ;; 61) modifiers=393216 ;; 64) modifiers=1048576 ;; 65) modifiers=1572864 ;; esac
    add_hotkey "$work" "$identifier" "$modifiers" || return 1
  done
  if ! "$defaults_bin" import com.apple.symbolichotkeys "$work" >/dev/null 2>&1; then
    restore_domain com.apple.symbolichotkeys || warn 'hotkey rollback failed; backup retained'
    return 1
  fi
}

apply_switch_mode() {
  local state=0
  [[ $input_switch != caps-lock ]] || state=1
  backup_domain input-switch NSGlobalDomain || return 1
  # Keep native Caps Lock switching off when using the confirmed shortcut path.
  if ! "$defaults_bin" write NSGlobalDomain TISRomanSwitchState -int "$state"; then
    restore_domain NSGlobalDomain || warn 'input-switch rollback failed; backup retained'
    return 1
  fi
}

enable_korean() {
  local app
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then
    app=$(bash "$(dirname -- "$0")/scripts/install-gureum.sh") || return 1
    /usr/bin/swift "$(dirname -- "$0")/enable-korean.swift" "$app" || return $?
  fi
}

reload_hotkeys() {
  # The Swift writer already reloads bindings. Confirm again in a fresh process.
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then
    /usr/bin/swift "$(dirname -- "$0")/enable-korean.swift" --verify-shortcuts
  fi
}

# Run independent groups even when an earlier group fails. Return a failure
# summary so callers can report incomplete preferences while continuing setup.
preference_status=0
run_group() {
  local group=$1
  shift
  if "$@"; then
    return 0
  else
    local status=$?
    warn "$group failed (exit $status); continuing remaining groups"
    preference_status=1
  fi
}

if [[ ${1:-} == --desktop-only ]]; then
  run_group dock apply_dock
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then /usr/bin/swift "$(dirname -- "$0")/scripts/quiet-desktop.swift"; fi
  exit "$preference_status"
fi

if [[ ${1:-} != --input-only && ${1:-} != --shortcuts-only ]]; then
  run_group text apply_text
  if [[ $dock_setup == 1 ]]; then run_group dock apply_dock; fi
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then
    run_group desktop /usr/bin/swift "$(dirname -- "$0")/scripts/quiet-desktop.swift"
  fi
fi
if [[ ${1:-} != --shortcuts-only ]]; then
  run_group input-sources apply_input_sources
  run_group gureum enable_korean
fi
run_group input-switch apply_switch_mode
run_group shortcuts apply_hotkeys
run_group shortcut-verification reload_hotkeys
if [[ $preference_status == 0 ]]; then
  printf 'macOS preferences applied. Backups: %s\n' "$backup_root"
else
  printf 'macOS preferences partially applied; review warnings. Backups: %s\n' "$backup_root" >&2
fi
exit "$preference_status"
