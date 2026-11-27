#!/bin/bash
# tests/p10k/segments.sh [FILTER] : one segment at a time, real p10k vs the
# port. Each case is "NAME|SEGMENTS|SHELL LINES"; the lines (valid in zsh and
# bash) are put before the template, the segments become the right prompt.
# Each case runs with the rainbow and the lean template.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; S=$T/seg; mkdir -p "$S" "$T/golden"
export GOLDEN_TTY_AGE=-1
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
: >"$T/hist-empty"
# Anchor the private fixture tree so unrelated siblings in /tmp cannot
# change a shortest-unique path between the two captures.
fixture=$(mktemp -d /tmp/b4h-fixture.XXXXXXXX) || exit 1
trap 'rm -rf -- "$fixture"' EXIT
: >"$fixture/.shorten_folder_marker"
L=$fixture/lang; "$root/tests/p10k/make-lang-fixtures.sh" "$L" >/dev/null || exit 1
# lines shared by the language cases: fake tools first on PATH, *_ROOT dirs
LP="export PATH=$L/bin:\$PATH HOME_FIX=$L/home RBENV_ROOT=$L/home/.rbenv GOENV_ROOT=$L/home/.goenv NODENV_ROOT=$L/home/.nodenv JENV_ROOT=$L/home/.jenv LUAENV_ROOT=$L/home/.luaenv PLENV_ROOT=$L/home/.plenv PHPENV_ROOT=$L/home/.phpenv SCALAENV_ROOT=$L/home/.scalaenv PYENV_ROOT=$L/home/.pyenv"
# Case fields: NAME|SEGMENTS|SHELL LINES|m (mask digits)|DIRECTORY|ENVIRONMENT
# (ENVIRONMENT: VAR=VALUE words set before either shell starts)
declare -a cases=(
  "ranger|ranger|export RANGER_LEVEL=1"
  "ranger-off|ranger|unset RANGER_LEVEL"
  "yazi|yazi|export YAZI_LEVEL=2"
  "nnn|nnn|export NNNLVL=1"
  "nnn-0|nnn|export NNNLVL=0"
  "lf|lf|export LF_LEVEL=1"
  "xplr|xplr|export XPLR_PID=123"
  "vim|vim_shell|export VIMRUNTIME=/usr/share/vim"
  "mc|midnight_commander|export MC_TMPDIR=/tmp/mc"
  "chezmoi|chezmoi_shell|export CHEZMOI=1"
  "nix-pure|nix_shell|export IN_NIX_SHELL=pure"
  "nix-1|nix_shell|export IN_NIX_SHELL=1"
  "nix-0|nix_shell|export IN_NIX_SHELL=0"
  "nix-path|nix_shell|unset IN_NIX_SHELL; export PATH=/nix/store/abc-x/bin:\$PATH; POWERLEVEL9K_NIX_SHELL_INFER_FROM_PATH=true"
  "toolbox|toolbox|export P9K_TOOLBOX_NAME=box"
  "direnv|direnv|export DIRENV_DIR=-/tmp"
  "ssh|ssh context|true|||SSH_CLIENT=10.0.0.1"
  "ssh-off|ssh|true"
  "root|root_indicator|true"
  "writable|dir_writable|true"
  "history|history|HISTFILE=$T/hist-empty"
  "proxy1|proxy|export http_proxy=http://u:p@proxy.example:3128/x https_proxy=http://proxy.example:3128"
  "proxy2|proxy|export http_proxy=http://a.example:1 HTTPS_PROXY=http://b.example:2"
  "load|load|true|m"
  "load-crit|load|POWERLEVEL9K_LOAD_CRITICAL_PCT=0|m"
  "ram|ram|true|m"
  "swap|swap|true|m"
  "disk|disk_usage|true|m"
  "disk-warn|disk_usage|POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL=1|m"
  "disk-only|disk_usage|POWERLEVEL9K_DISK_USAGE_ONLY_WARNING=true|m"
  "arch|cpu_arch|true"
  "virt|detect_virt|true"
  "rbenv-local|rbenv|$LP||$L/proj/sub"
  "rbenv-global|rbenv|$LP||$L/home"
  "rbenv-always|rbenv|$LP; POWERLEVEL9K_RBENV_PROMPT_ALWAYS_SHOW=true||$L/home"
  "rbenv-shell|rbenv|$LP; export RBENV_VERSION=2.7.8||$L/home"
  "rbenv-dir|rbenv|$LP; export RBENV_DIR=$L/proj/sub||/tmp"
  "goenv|goenv|$LP||$L/proj"
  "goenv-shell|goenv|$LP; export GOENV_VERSION=go-1.19:1.18||$L/proj"
  "nodenv|nodenv|$LP||$L/proj"
  "jenv|jenv|$LP||$L/proj"
  "luaenv|luaenv|$LP||$L/proj"
  "plenv|plenv|$LP||$L/proj"
  "phpenv|phpenv|$LP||$L/proj"
  "scalaenv|scalaenv|$LP||$L/proj"
  "pyenv|pyenv|$LP||$L/proj"
  "pyenv-venv|virtualenv pyenv|$LP; export VIRTUAL_ENV=$L/home/work/myproj/venv||$L/proj"
  "venv-generic|virtualenv|$LP; export VIRTUAL_ENV=$L/home/work/myproj/venv||/tmp"
  "venv-cfg|virtualenv|$LP; export VIRTUAL_ENV=$L/home/cfgenv||/tmp"
  "venv-prompt|virtualenv|$LP; export VIRTUAL_ENV=$L/home/work/myproj/venv VIRTUAL_ENV_PROMPT='(other) '||/tmp"
  "venv-pyver|virtualenv|$LP; export VIRTUAL_ENV=$L/home/cfgenv; POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=true||/tmp"
  "venv-ifdiff|virtualenv pyenv|$LP; export VIRTUAL_ENV=$L/home/work/myproj/3.12.1; POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=if-different||$L/proj"
  "anaconda|anaconda|$LP; export CONDA_PREFIX=/opt/conda/envs/ds||/tmp"
  "nodeenv|nodeenv|$LP; export NODE_VIRTUAL_ENV=/x/env; POWERLEVEL9K_NODEENV_SHOW_NODE_VERSION=true||/tmp"
  "nvm|nvm|$LP; export NVM_DIR=$L/home/nvm PATH=$L/home/nvm/versions/node/v20.10.0/bin:\$PATH; nvm() { :; }||/tmp"
  "rvm|rvm|$LP; export GEM_HOME=/h/.rvm/gems/ruby-3.2.0@proj||/tmp"
  "chruby|chruby|$LP; export RUBY_ENGINE=ruby RUBY_VERSION=3.3.0||/tmp"
  "perlbrew|perlbrew|$LP; export PERLBREW_PERL=perl-5.38.0||/tmp"
  "perlbrew-proj|perlbrew|$LP; export PERLBREW_PERL=perl-5.38.0; POWERLEVEL9K_PERLBREW_PROJECT_ONLY=true||/tmp"
  "fvm|fvm|$LP||$L/proj/sub"
  "stack|haskell_stack|$LP||$L/proj"
  # asdf: the real HOME is kept (zsh's line editor misbehaves in this harness
  # when HOME changes); ASDF_DATA_DIR points at the fixture, whose
  # .tool-versions files lie in parent directories of the project
  "asdf-proj|asdf|$LP; export ASDF_DATA_DIR=$L/home/asdfhome/.asdf||$L/home/asdfhome/proj/sub"
  "asdf-top|asdf|$LP; export ASDF_DATA_DIR=$L/home/asdfhome/.asdf||$L/home/asdfhome"
  "asdf-always|asdf|$LP; export ASDF_DATA_DIR=$L/home/asdfhome/.asdf; POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW=true||$L/home/asdfhome/proj"
  "asdf-shell|asdf|$LP; export ASDF_DATA_DIR=$L/home/asdfhome/.asdf ASDF_RUBY_VERSION=2.7.0||$L/home/asdfhome/proj"
  "asdf-default|asdf|$LP; export ASDF_DATA_DIR=$L/home/asdfhome/.asdf ASDF_DEFAULT_TOOL_VERSIONS_FILENAME=$L/home/asdfhome/.tool-versions||$L/home/asdfhome/proj/sub"
  "node-ver|node_version|$LP||$L/proj"
  "node-ver-po|node_version|$LP; POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true||/tmp"
  "go-ver|go_version|$LP||$L/proj"
  "go-ver-po|go_version|$LP; export GOPATH=/nonexistent||/tmp"
  "rust-ver|rust_version|$LP||$L/proj"
  "rust-ver-po|rust_version|$LP||/tmp"
  "java-ver|java_version|$LP||/tmp"
  "java-full|java_version|$LP; POWERLEVEL9K_JAVA_VERSION_FULL=true||/tmp"
  "php-ver|php_version|$LP||$L/proj"
  "dotnet-ver|dotnet_version|$LP||/tmp"
  "swift-ver|swift_version|$LP||/tmp"
  "package|package|$LP||$L/proj/sub"
  "kube|kubecontext|$LP; export KUBE_FIX=$L/cloud/kube/plain.yaml KUBECONFIG=$L/cloud/kube/config||/tmp"
  "kube-gke|kubecontext|$LP; export KUBE_FIX=$L/cloud/kube/gke.yaml KUBECONFIG=$L/cloud/kube/config||/tmp"
  "kube-class|kubecontext|$LP; export KUBE_FIX=$L/cloud/kube/plain.yaml KUBECONFIG=$L/cloud/kube/config; POWERLEVEL9K_KUBECONTEXT_CLASSES=('*dev*' TEST '*' DEFAULT)||/tmp"
  "tf|terraform|$LP||$L/cloud/tf"
  "tf-ver|terraform_version|$LP||$L/cloud/tf"
  "eb|aws_eb_env|$LP||$L/cloud/eb"
  "azure|azure|$LP; export AZURE_CONFIG_DIR=$L/cloud/azure||/tmp"
  "gcloud|gcloud|$LP; export CLOUDSDK_CONFIG=$L/cloud/gcloud||/tmp"
  "aws|aws|$LP; export AWS_PROFILE=default AWS_CONFIG_FILE=$L/cloud/aws-config||/tmp"
  "aws-quoted|aws|$LP; export AWS_PROFILE='prod team' AWS_CONFIG_FILE=$L/cloud/aws-config||/tmp"
  "gcred|google_app_cred|$LP; export GOOGLE_APPLICATION_CREDENTIALS=$L/cloud/gcred.json||/tmp"
  "docker-m|docker_machine|export DOCKER_MACHINE_NAME=box1||/tmp"
  "upglob-hide|ranger|export RANGER_LEVEL=1; POWERLEVEL9K_RANGER_SHOW_ON_UPGLOB='nomatch.xyz|*.zzz'||$L/proj/sub"
  "upglob-show|ranger|export RANGER_LEVEL=1; POWERLEVEL9K_RANGER_SHOW_ON_UPGLOB='*.zzz|go.mod'||$L/proj/sub"
)
pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id segs pre mask dir genv <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  [[ -n $dir ]] || dir=/tmp; [[ $id == writable ]] && dir=/
  for tpl in rainbow lean; do
    for sh in zsh bash; do
      src=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh
      [[ $sh == bash ]] && src=$root/p10k/config/p10k-$tpl.bash
      { echo "$pre"; cat "$src"; echo "$pre"   # before: environment; after: settings (templates unset POWERLEVEL9K_*)
        echo "POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir)"
        echo "POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=($segs)"; } >"$S/$id-$tpl.$sh"
    done
    if GOLDEN_ENV=$genv MASK_DIGITS=${mask:+1} "$root/tests/p10k/golden.sh" "seg-$id-$tpl" "$S/$id-$tpl.zsh" "$S/$id-$tpl.bash" "$dir" 80 4 \
         >"$T/golden/seg-$id-$tpl.log" 2>&1; then
      (( pass++ )); echo "SAME  $id-$tpl"
    else
      (( fail++ )); echo "DIFF  $id-$tpl  $(sed -n 1p "$T/golden/seg-$id-$tpl.log" | grep -o '([0-9]* cells)')"
    fi
  done
done
for tty in new old; do
  [[ -z ${1-} || tty-$tty == *"$1"* ]] || continue
  age=-1 row=1
  [[ $tty != old ]] || { age=0; row=2; }
  if GOLDEN_TTY_AGE=$age GOLDEN_FIRST_ROW=$row "$root/tests/p10k/golden.sh" "tty-$tty" \
       "$HOME/src/powerlevel10k/config/p10k-lean.zsh" "$root/p10k/config/p10k-lean.bash" /tmp; then
    (( pass++ ))
  else
    (( fail++ ))
  fi
done
echo "same: $pass   different: $fail"
(( fail == 0 ))
