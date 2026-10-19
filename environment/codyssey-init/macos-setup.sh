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

[[ $($uname_bin -s) == Darwin ]] || {
  printf 'macos-setup.sh only supports macOS.\n' >&2
  exit 1
}

input_switch=${CODYSSEY_INPUT_SWITCH:-}
dock_setup=${CODYSSEY_DOCK_SETUP:-}
case ${1:-} in
  '') ;;
  --input-only|--no-dock) dock_setup=0 ;;
  --shortcuts-only) input_switch=control-space; dock_setup=0 ;;
  *) printf 'Usage: bash macos-setup.sh [--input-only | --no-dock | --shortcuts-only]\n' >&2; exit 2 ;;
esac
# Use the controlling terminal so curl | sh does not consume installer text.
if [[ -t 1 ]] && { true </dev/tty && true >/dev/tty; } 2>/dev/null; then
  while [[ -z $input_switch ]]; do
    printf 'Korean/English switching: [1] Control-Space (Gureum) [2] Caps Lock (requires compatible input source) (default 1): ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=1
    case $answer in
      ''|1) input_switch=control-space ;;
      2) input_switch=caps-lock ;;
      *) printf 'Choose 1 or 2.\n' >/dev/tty ;;
    esac
  done
  if [[ -z $dock_setup ]]; then
    printf 'Keep only Terminal and Chrome pinned in the Dock, and remove stacks/recent apps? [y/N] ' >/dev/tty
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
  listed=$($defaults_bin domains 2>/dev/null) || return 2
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

apply_dock() {
  local terminal_app chrome_app terminal_url chrome_url failed=0
  backup_domain dock com.apple.dock || return
  terminal_app="$system_applications_dir/Utilities/Terminal.app"
  chrome_app="$applications_dir/Google Chrome.app"
  [[ -d $chrome_app ]] || chrome_app="$HOME/Applications/Google Chrome.app"
  if [[ ! -d $terminal_app || ! -d $chrome_app ]]; then
    return
  fi
  terminal_url="file://${terminal_app// /%20}/"
  chrome_url="file://${chrome_app// /%20}/"
  "$defaults_bin" write com.apple.dock persistent-apps -array \
    "{tile-data={file-data={_CFURLString=\"$terminal_url\";_CFURLStringType=15;};};tile-type=\"file-tile\";}" \
    "{tile-data={file-data={_CFURLString=\"$chrome_url\";_CFURLStringType=15;};};tile-type=\"file-tile\";}" >/dev/null 2>&1 || failed=1
  "$defaults_bin" write com.apple.dock persistent-others -array >/dev/null 2>&1 || failed=1
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
    kind=$($plistbuddy_bin -c "Print :AppleEnabledInputSources:$index:InputSourceKind" "$work" 2>/dev/null || true)
    bundle=$($plistbuddy_bin -c "Print :AppleEnabledInputSources:$index:'Bundle ID'" "$work" 2>/dev/null || true)
    mode=$($plistbuddy_bin -c "Print :AppleEnabledInputSources:$index:'Input Mode'" "$work" 2>/dev/null || true)
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
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:0 integer 32" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:1 integer 49" "$work" &&
    "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:value:parameters:2 integer $modifiers" "$work"
}

apply_hotkeys() {
  local work identifier keycode modifiers conflicts=0
  backup_domain hotkeys com.apple.symbolichotkeys || return
  if [[ $defaults_bin == defaults && -x /usr/bin/swift ]]; then
    /usr/bin/swift "$(dirname -- "$0")/enable-korean.swift" --shortcuts
    return $?
  fi
  work=$(mktemp "$backup_root/hotkeys.work.XXXXXX") || return
  if [[ $BACKUP_KIND == present ]]; then
    cp "$BACKUP_PATH" "$work"
  else
    "$plutil_bin" -create xml1 "$work" || return
  fi
  "$plistbuddy_bin" -c 'Print :AppleSymbolicHotKeys' "$work" >/dev/null 2>&1 ||
    "$plistbuddy_bin" -c 'Add :AppleSymbolicHotKeys dict' "$work" || { warn 'hotkey map is unreadable'; return; }
  # Spotlight can also own Control-Space on localized macOS installations.
  # Preserve its other bindings; disable only conflicts with input switching.
  for identifier in 64 65; do
    keycode=$($plistbuddy_bin -c "Print :AppleSymbolicHotKeys:$identifier:value:parameters:1" "$work" 2>/dev/null || true)
    modifiers=$($plistbuddy_bin -c "Print :AppleSymbolicHotKeys:$identifier:value:parameters:2" "$work" 2>/dev/null || true)
    if [[ $keycode == 49 && ( $modifiers == 262144 || $modifiers == 393216 ) ]]; then
      "$plistbuddy_bin" -c "Delete :AppleSymbolicHotKeys:$identifier:enabled" "$work" >/dev/null 2>&1 || true
      "$plistbuddy_bin" -c "Add :AppleSymbolicHotKeys:$identifier:enabled bool false" "$work" || { warn 'Spotlight conflict could not be disabled'; return; }
      conflicts=1
    fi
  done
  # Unregister Spotlight's claim before registering the same key for input
  # switching; a single reload can otherwise retain the old live binding.
  if [[ $conflicts == 1 ]]; then
    if ! "$defaults_bin" import com.apple.symbolichotkeys "$work" >/dev/null 2>&1; then
      restore_domain com.apple.symbolichotkeys || warn 'hotkey rollback failed; backup retained'
      return 1
    fi
    reload_hotkeys || return 1
  fi
  add_hotkey "$work" 60 262144 && add_hotkey "$work" 61 393216 || { warn 'hotkey update could not be prepared'; return 1; }
  if ! "$defaults_bin" import com.apple.symbolichotkeys "$work" >/dev/null 2>&1; then
    restore_domain com.apple.symbolichotkeys || warn 'hotkey rollback failed; backup retained'
    warn 'hotkey write failed'
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

if [[ ${1:-} == --shortcuts-only ]]; then
  apply_switch_mode && apply_hotkeys && reload_hotkeys || exit 1
  printf 'Shortcut settings applied; input sources unchanged. Backups: %s\n' "$backup_root"
  exit 0
fi

if [[ ${1:-} == --input-only ]]; then
  apply_input_sources
  keyboard_status=0
  enable_korean || keyboard_status=$?
  [[ $keyboard_status == 0 ]] || exit "$keyboard_status"
  apply_switch_mode || exit 1
  if [[ $input_switch == control-space ]]; then apply_hotkeys || exit 1; fi
  reload_hotkeys || exit 1
  printf 'Korean input configured with %s switching. Test Korean and English in a text field. Backups: %s\n' "$input_switch" "$backup_root"
  exit 0
fi

apply_text
[[ $dock_setup != 1 ]] || apply_dock
apply_input_sources
keyboard_status=0
enable_korean || keyboard_status=$?
[[ $keyboard_status == 0 ]] || exit "$keyboard_status"
apply_switch_mode || exit 1
if [[ $input_switch == control-space ]]; then apply_hotkeys || exit 1; fi
reload_hotkeys || exit 1
printf 'macOS preferences applied with group isolation. Backups: %s\n' "$backup_root"
exit 0
