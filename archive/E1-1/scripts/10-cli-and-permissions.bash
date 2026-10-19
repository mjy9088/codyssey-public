#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "10-cli-and-permissions"

demo_dir="$(mktemp -d /tmp/workstation-cli.XXXXXX)"
trap 'rm -rf "$demo_dir"' EXIT

section "Navigation and file operations"
working_directory="$(pwd)"
printf '%s\n' "$working_directory"
assert_eq "working directory" "/workspace" "$working_directory"
ls -la
mkdir -p "$demo_dir/source" "$demo_dir/archive"
assert_eq "source directory created" "directory" \
  "$(test -d "$demo_dir/source" && printf directory)"
assert_eq "archive directory created" "directory" \
  "$(test -d "$demo_dir/archive" && printf directory)"
touch "$demo_dir/source/empty.txt"
assert_eq "empty file created" "file" \
  "$(test -f "$demo_dir/source/empty.txt" && printf file)"
assert_eq "empty file size" "0" \
  "$(stat -c '%s' "$demo_dir/source/empty.txt")"
sh -c 'printf "reproducible\n" > "$1"' _ "$demo_dir/source/note.txt"
note_contents="$(cat "$demo_dir/source/note.txt")"
printf '%s\n' "$note_contents"
assert_eq "note contents" "reproducible" "$note_contents"
cp "$demo_dir/source/note.txt" "$demo_dir/archive/copy.txt"
assert_eq "copy preserves contents" "$note_contents" \
  "$(cat "$demo_dir/archive/copy.txt")"
assert_eq "copy preserves source" "file" \
  "$(test -f "$demo_dir/source/note.txt" && printf file)"
mv "$demo_dir/archive/copy.txt" "$demo_dir/archive/renamed.txt"
ls -la "$demo_dir/archive"
assert_eq "move removes old path" "missing" \
  "$(test ! -e "$demo_dir/archive/copy.txt" && printf missing)"
assert_eq "move preserves contents" "$note_contents" \
  "$(cat "$demo_dir/archive/renamed.txt")"
rm "$demo_dir/source/empty.txt"
assert_eq "remove deletes file" "missing" \
  "$(test ! -e "$demo_dir/source/empty.txt" && printf missing)"
nested_listing="$(sh -c 'cd "$1" && pwd && ls -la ../archive' _ "$demo_dir/source")"
printf '%s\n' "$nested_listing"
assert_contains "relative navigation directory" "$nested_listing" "$demo_dir/source"
assert_contains "relative archive listing" "$nested_listing" "renamed.txt"

section "File permission: 600 to 644"
chmod 600 "$demo_dir/source/note.txt"
stat -c '%A %a %n' "$demo_dir/source/note.txt"
assert_eq "restricted file mode" "600" \
  "$(stat -c '%a' "$demo_dir/source/note.txt")"
chmod 644 "$demo_dir/source/note.txt"
stat -c '%A %a %n' "$demo_dir/source/note.txt"
assert_eq "file mode" "644" \
  "$(stat -c '%a' "$demo_dir/source/note.txt")"

section "Directory permission: 700 to 755"
chmod 700 "$demo_dir/archive"
stat -c '%A %a %n' "$demo_dir/archive"
assert_eq "restricted directory mode" "700" \
  "$(stat -c '%a' "$demo_dir/archive")"
chmod 755 "$demo_dir/archive"
stat -c '%A %a %n' "$demo_dir/archive"
assert_eq "directory mode" "755" \
  "$(stat -c '%a' "$demo_dir/archive")"

end_validation
