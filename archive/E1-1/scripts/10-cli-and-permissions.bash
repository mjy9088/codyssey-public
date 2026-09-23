#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "10-cli-and-permissions"

demo_dir="$(mktemp -d /tmp/workstation-cli.XXXXXX)"
trap 'rm -rf "$demo_dir"' EXIT

section "Navigation and file operations"
pwd
ls -la
mkdir -p "$demo_dir/source" "$demo_dir/archive"
touch "$demo_dir/source/empty.txt"
sh -c 'printf "reproducible\n" > "$1"' _ "$demo_dir/source/note.txt"
cat "$demo_dir/source/note.txt"
cp "$demo_dir/source/note.txt" "$demo_dir/archive/copy.txt"
mv "$demo_dir/archive/copy.txt" "$demo_dir/archive/renamed.txt"
ls -la "$demo_dir/archive"
rm "$demo_dir/source/empty.txt"
sh -c 'cd "$1" && pwd && ls -la ../archive' _ "$demo_dir/source"

section "File permission: 600 to 644"
chmod 600 "$demo_dir/source/note.txt"
stat -c '%A %a %n' "$demo_dir/source/note.txt"
chmod 644 "$demo_dir/source/note.txt"
stat -c '%A %a %n' "$demo_dir/source/note.txt"
assert_eq "file mode" "644" \
  "$(stat -c '%a' "$demo_dir/source/note.txt")"

section "Directory permission: 700 to 755"
chmod 700 "$demo_dir/archive"
stat -c '%A %a %n' "$demo_dir/archive"
chmod 755 "$demo_dir/archive"
stat -c '%A %a %n' "$demo_dir/archive"
assert_eq "directory mode" "755" \
  "$(stat -c '%a' "$demo_dir/archive")"

end_validation
