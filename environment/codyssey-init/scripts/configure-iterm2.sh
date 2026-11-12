#!/usr/bin/env bash
# Modify only the default profile's two keyboard settings, using user preferences.
set -euo pipefail
umask 077
[[ $(uname -s) == Darwin ]] || { printf 'iTerm2 preferences require macOS.\n' >&2; exit 1; }
defaults_bin=${DEFAULTS_BIN:-defaults}
plistbuddy_bin=${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}
plutil_bin=${PLUTIL_BIN:-plutil}
pgrep_bin=${PGREP_BIN:-pgrep}
domain=com.googlecode.iterm2
if "$pgrep_bin" -u "$(id -u)" -x iTerm2 >/dev/null; then
  printf 'Quit iTerm2, then run the same init command from Terminal to apply its keyboard settings.\n' >&2
  exit 1
fi
stage=$(mktemp -d)
original="$stage/original.plist"
work="$stage/preferences.plist"
present=0 write_started=0 backup=
restore_preferences() {
  if [[ $present == 1 ]]; then "$defaults_bin" import "$domain" "$original"; else
    "$defaults_bin" delete "$domain"
  fi
}
cleanup() {
  result=$?
  trap - EXIT
  if [[ $write_started == 1 ]]; then
    if ! restore_preferences >/dev/null 2>&1; then
      printf 'iTerm2 preference rollback failed. Backup: %s\n' "$backup" >&2
    fi
    result=1
  fi
  rm -rf "$stage"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if "$defaults_bin" export "$domain" "$original" >/dev/null 2>&1; then
  present=1
else
  # Confirm absence before creating preferences; export failure is not absence.
  domains=$("$defaults_bin" domains)
  if printf '%s\n' "$domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fxq "$domain" \
    || [[ -e $HOME/Library/Preferences/$domain.plist || -L $HOME/Library/Preferences/$domain.plist ]]; then
    printf 'Could not read existing iTerm2 preferences; preserving them.\n' >&2
    exit 1
  fi
  "$plutil_bin" -create xml1 "$original"
fi
cp "$original" "$work"
read_value() { "$plutil_bin" -extract "$1" raw "$work" 2>/dev/null || true; }
read_type() { "$plutil_bin" -type "$1" "$work" 2>/dev/null || true; }
custom=$(read_value LoadPrefsFromCustomFolder)
[[ $custom != true && $custom != 1 ]] || {
  printf 'iTerm2 uses a custom preferences folder; preserving that configuration.\n' >&2; exit 1;
}
default_guid=$(read_value 'Default Bookmark Guid')
kind=$(read_type 'New Bookmarks')
if [[ -z $kind ]]; then
  [[ -z $default_guid ]] || { printf 'Could not resolve the default iTerm2 profile.\n' >&2; exit 1; }
  "$plistbuddy_bin" -c "Add :'New Bookmarks' array" "$work"
elif [[ $kind != array ]]; then
  printf 'iTerm2 profiles are unreadable; preserving existing preferences.\n' >&2; exit 1
fi
count=$(read_value 'New Bookmarks')
[[ $count =~ ^[0-9]+$ ]] || exit 1
if [[ $count == 0 ]]; then
  [[ -z $default_guid ]] || { printf 'Could not resolve the default iTerm2 profile.\n' >&2; exit 1; }
  default_guid=CE86AC28-8A7B-4BA8-B909-AC9D0AB86B42
  "$plistbuddy_bin" -c "Add :'New Bookmarks':0 dict" "$work"
  "$plistbuddy_bin" -c "Add :'New Bookmarks':0:Name string Default" "$work"
  "$plistbuddy_bin" -c "Add :'New Bookmarks':0:Guid string $default_guid" "$work"
  "$plutil_bin" -replace 'Default Bookmark Guid' -string "$default_guid" "$work"
  count=1
fi
selected=-1
for ((index=0; index<count; index++)); do
  guid=$(read_value "New Bookmarks.$index.Guid")
  if [[ -n $guid && ( $guid == "$default_guid" || ( -z $default_guid && $index == 0 ) ) ]]; then selected=$index; break; fi
done
[[ $selected != -1 ]] || { printf 'Could not resolve the default iTerm2 profile.\n' >&2; exit 1; }
option="New Bookmarks.$selected.Option Key Sends"
reporting="New Bookmarks.$selected.Allow modifyOtherKeys"
if [[ $(read_type "$option") == integer && $(read_value "$option") == 2 \
  && $(read_type "$reporting") == bool && $(read_value "$reporting") == true ]]; then
  printf 'iTerm2 keyboard settings are already configured.\n'
  exit 0
fi
"$plutil_bin" -replace "$option" -integer 2 "$work"
"$plutil_bin" -replace "$reporting" -bool true "$work"
backup_parent="$HOME/Library/Application Support/codyssey-init/iterm2-backups"
mkdir -p "$backup_parent"
chmod 0700 "$backup_parent"
backup=$(mktemp -d "$backup_parent/run.XXXXXX")
if [[ $present == 1 ]]; then cp "$original" "$backup/preferences.plist"; else : >"$backup/preferences.missing"; fi
write_started=1
"$defaults_bin" import "$domain" "$work" >/dev/null
write_started=0
printf 'iTerm2 default profile: Left Option = Esc+; apps may change key reporting.\n'
