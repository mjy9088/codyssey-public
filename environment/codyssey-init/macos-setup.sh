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
    if [[ $kind == 'Input Mode' && $bundle == 'com.apple.inputmethod.Korean' && $mode == 'com.apple.inputmethod.Korean.2SetKorean' ]]; then
      return
    fi
    index=$((index + 1))
  done
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index dict" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:InputSourceKind string 'Input Mode'" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:'Bundle ID' string 'com.apple.inputmethod.Korean'" "$work" || failed=1
  "$plistbuddy_bin" -c "Add :AppleEnabledInputSources:$index:'Input Mode' string 'com.apple.inputmethod.Korean.2SetKorean'" "$work" || failed=1
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
  local work
  backup_domain hotkeys com.apple.symbolichotkeys || return
  work=$(mktemp "$backup_root/hotkeys.work.XXXXXX") || return
  if [[ $BACKUP_KIND == present ]]; then
    cp "$BACKUP_PATH" "$work"
  else
    "$plutil_bin" -create xml1 "$work" || return
  fi
  "$plistbuddy_bin" -c 'Print :AppleSymbolicHotKeys' "$work" >/dev/null 2>&1 ||
    "$plistbuddy_bin" -c 'Add :AppleSymbolicHotKeys dict' "$work" || { warn 'hotkey map is unreadable'; return; }
  add_hotkey "$work" 60 262144 && add_hotkey "$work" 61 786432 || { warn 'hotkey update could not be prepared'; return; }
  if ! "$defaults_bin" import com.apple.symbolichotkeys "$work" >/dev/null 2>&1; then
    restore_domain com.apple.symbolichotkeys || warn 'hotkey rollback failed; backup retained'
    warn 'hotkey write failed'
  fi
}

apply_text
apply_dock
apply_input_sources
apply_hotkeys
printf 'macOS preferences applied with group isolation. Backups: %s\n' "$backup_root"
exit 0
