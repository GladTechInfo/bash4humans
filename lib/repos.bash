# =============================================================================
#  lib/repos.bash - plugins from any GitHub repository (zsh4humans' z4h install)
#
#    b4h install USER/REPO[@REF]...   download it (once; later starts do nothing)
#    b4h load USER/REPO[/DIR]...      load the plugin in it (or in DIR inside it)
#    b4h source USER/REPO/FILE...     source one file from it
#    b4h uninstall USER/REPO...       delete the download
#    b4h update                       also brings each repository up to date
#
#  In ~/.bashrc, after bash4humans is loaded, for example:
#    b4h install zsh-users/zsh-completions
#    b4h load    USER/REPO
#  A repository is cloned with git, one commit deep, from its default branch
#  (or from REF: a branch, tag or commit) into $B4H_HOME/repos/USER/REPO.
#  Its code runs in your shell, as any plugin's does: install what you trust.
# =============================================================================

_b4h_repos_dir=$B4H_HOME/repos

# USER/REPO: letters, digits, . _ - (as GitHub's names); never .. or a path.
_b4h_repo_name_ok() {
  [[ $1 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $1 != *..* ]]
}

# Clone (or fetch again) one repository into DIR: REF empty = default branch.
_b4h_repo_fetch() {
  local name=$1 ref=$2 dir=$_b4h_repos_dir/$1
  local url=$B4H_GIT_BASE/$name tmp=$dir.tmp.$$
  rm -rf -- "$tmp"; mkdir -p -- "${dir%/*}" || return 1
  if [[ -z $ref ]]; then
    git clone -q --depth 1 -- "$url" "$tmp" 2>/dev/null || { rm -rf -- "$tmp"; return 1; }
  else
    # a branch, a tag or a commit: fetch exactly that, one commit deep
    { git init -q "$tmp" && git -C "$tmp" remote add origin "$url" &&
      git -C "$tmp" fetch -q --depth 1 origin "$ref" &&
      git -C "$tmp" checkout -q FETCH_HEAD; } 2>/dev/null || { rm -rf -- "$tmp"; return 1; }
    git -C "$tmp" config b4h.ref "$ref"
  fi
  rm -rf -- "$dir" && mv -- "$tmp" "$dir"
}

_b4h_repo_install() {
  local spec name ref rc=0 failed
  command -v git >/dev/null || { echo 'b4h install: needs git' >&2; return 1; }
  for spec; do
    name=${spec%%@*} ref=
    [[ $spec == *@* ]] && ref=${spec#*@}
    _b4h_repo_name_ok "$name" || { echo "b4h install: '$spec' is not USER/REPO[@REF]" >&2; rc=1; continue; }
    [[ -d $_b4h_repos_dir/$name/.git ]] && continue          # installed: nothing to do
    # A download that failed is not tried at every start; b4h update tries again.
    failed=$_b4h_repos_dir/.failed-${name/\//--}
    [[ -e $failed ]] && { rc=1; continue; }
    echo "b4h install: $name ..."
    if _b4h_repo_fetch "$name" "$ref"; then
      echo "b4h install: $name $(git -C "$_b4h_repos_dir/$name" log -1 --format='%h %cs')"
    else
      mkdir -p -- "$_b4h_repos_dir" && : >"$failed"
      echo "b4h install: $name could not be downloaded from $B4H_GIT_BASE (b4h update tries again)" >&2
      rc=1
    fi
  done
  return "$rc"
}

# The plugin file of a directory NAME: NAME.plugin.bash, NAME.bash,
# NAME.plugin.sh, NAME.sh, init.bash, init.sh, or the only *.plugin.bash /
# *.bash there is.
_b4h_repo_plugin_file() {
  local d=$1 n=${1##*/} f
  local -a found
  for f in "$d/$n.plugin.bash" "$d/$n.bash" "$d/$n.plugin.sh" "$d/$n.sh" "$d/init.bash" "$d/init.sh"; do
    [[ -f $f ]] && { REPLY=$f; return 0; }
  done
  for f in plugin.bash bash; do
    found=("$d"/*."$f")
    [[ ${#found[@]} == 1 && -f ${found[0]} ]] && { REPLY=${found[0]}; return 0; }
  done
  return 1
}

_b4h_repo_load() {
  local spec name dir rc=0 REPLY
  for spec; do
    name=${spec#*/}; name=${spec%%/*}/${name%%/*}             # USER/REPO
    dir=$_b4h_repos_dir/$spec
    if ! _b4h_repo_name_ok "$name" || [[ $spec == *..* ]]; then
      echo "b4h load: '$spec' is not USER/REPO[/DIR]" >&2; rc=1; continue
    fi
    [[ -d $_b4h_repos_dir/$name ]] || { echo "b4h load: $name is not installed (b4h install $name)" >&2; rc=1; continue; }
    if ! _b4h_repo_plugin_file "$dir"; then
      echo "b4h load: no plugin file in $spec (b4h source USER/REPO/FILE for one file)" >&2; rc=1; continue
    fi
    # a bin/ directory beside the plugin goes on PATH
    [[ -d $dir/bin && ":$PATH:" != *":$dir/bin:"* ]] && PATH=$dir/bin:$PATH
    . "$REPLY"
  done
  return "$rc"
}

_b4h_repo_source() {
  local spec file rc=0
  for spec; do
    file=$_b4h_repos_dir/$spec
    if [[ $spec != */*/* || $spec == *..* ]]; then
      echo "b4h source: '$spec' is not USER/REPO/FILE" >&2; rc=1
    elif [[ -f $file ]]; then
      . "$file"
    else
      echo "b4h source: no file $spec (installed? b4h install ${spec%%/*}/$(cut -d/ -f2 <<<"$spec"))" >&2; rc=1
    fi
  done
  return "$rc"
}

_b4h_repo_uninstall() {
  local name rc=0
  for name; do
    name=${name%%@*}
    _b4h_repo_name_ok "$name" || { echo "b4h uninstall: '$name' is not USER/REPO" >&2; rc=1; continue; }
    if [[ -d $_b4h_repos_dir/$name ]]; then
      rm -rf -- "${_b4h_repos_dir:?}/$name"
      rmdir -- "$_b4h_repos_dir/${name%%/*}" 2>/dev/null
      echo "b4h uninstall: $name deleted (remove its b4h install line from ~/.bashrc, or the next shell fetches it again)"
    else
      echo "b4h uninstall: $name is not installed" >&2; rc=1
    fi
  done
  return "$rc"
}

# b4h update: each repository to the newest commit of its branch (or REF);
# failed downloads are tried again at the next start.
_b4h_repos_update() {
  local d name ref old new
  rm -f -- "$_b4h_repos_dir"/.failed-* 2>/dev/null
  for d in "$_b4h_repos_dir"/*/*/.git; do
    [[ -d $d ]] || continue
    d=${d%/.git} name=${d#"$_b4h_repos_dir"/}
    ref=$(git -C "$d" config b4h.ref)
    old=$(git -C "$d" rev-parse --short HEAD)
    if git -C "$d" fetch -q --depth 1 origin "${ref:-HEAD}" 2>/dev/null &&
       git -C "$d" reset -q --hard FETCH_HEAD; then
      new=$(git -C "$d" rev-parse --short HEAD)
      [[ $old == "$new" ]] && echo "b4h update: $name up to date ($new)" || echo "b4h update: $name $old -> $new"
    else
      echo "b4h update: $name could not be updated" >&2
    fi
  done
}

# b4h plugins: the installed repositories, after the plugins
_b4h_repos_list() {
  local d any=
  for d in "$_b4h_repos_dir"/*/*/.git; do
    [[ -d $d ]] || continue
    [[ -n $any ]] || { echo; echo '  repositories (b4h install):'; any=1; }
    d=${d%/.git}
    printf '      %-30s %s%s\n' "${d#"$_b4h_repos_dir"/}" "$(git -C "$d" log -1 --format='%h %cs')" \
      "$(r=$(git -C "$d" config b4h.ref) && printf ' @%s' "$r")"
  done
}
