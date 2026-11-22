# about: z DIR - jump to a frequently used directory by part of its name (needs zoxide)
if command -v zoxide >/dev/null; then
  eval "$(zoxide init bash)"
else
  z() { echo 'z: install zoxide first (Arch: pacman -S zoxide, Debian: apt install zoxide)' >&2; return 1; }
fi
