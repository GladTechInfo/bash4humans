# about: extract FILE... - unpack any archive (tar.*, zip, 7z, rar, gz, bz2, xz, zst, deb, rpm, iso) into ./NAME/
extract() {
  (( $# )) || { echo 'usage: extract ARCHIVE...' >&2; return 2; }
  local f dir rc=0
  for f; do
    [[ -f $f ]] || { echo "extract: $f: no such file" >&2; rc=1; continue; }
    dir=${f##*/}; dir=${dir%.@(tar.*|tgz|tbz2|txz|tzst|zip|7z|rar|gz|bz2|xz|zst|deb|rpm|iso|tar)}
    mkdir -p -- "$dir" || { rc=1; continue; }
    case ${f,,} in
      *.tar.*|*.tgz|*.tbz2|*.txz|*.tzst|*.tar) tar -xf "$f" -C "$dir" ;;
      *.zip)  unzip -q "$f" -d "$dir" ;;
      *.7z)   7z x -o"$dir" "$f" >/dev/null ;;
      *.rar)  unrar x -idq "$f" "$dir/" ;;
      *.gz)   gzip -dc "$f" >"$dir/${dir##*/}" ;;
      *.bz2)  bzip2 -dc "$f" >"$dir/${dir##*/}" ;;
      *.xz)   xz -dc "$f" >"$dir/${dir##*/}" ;;
      *.zst)  zstd -qdc "$f" >"$dir/${dir##*/}" ;;
      *.deb)  (cd "$dir" && ar x "../$f") ;;
      *.rpm)  (cd "$dir" && rpm2cpio "../$f" | cpio -idm --quiet) ;;
      *.iso)  7z x -o"$dir" "$f" >/dev/null ;;
      *)      echo "extract: $f: unknown archive type" >&2; rmdir -- "$dir" 2>/dev/null; rc=1; continue ;;
    esac || { echo "extract: $f: failed (is the tool for it installed?)" >&2; rc=1; continue; }
    echo "extract: $f -> $dir/"
  done
  return $rc
}
