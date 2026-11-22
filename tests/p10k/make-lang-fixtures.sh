#!/bin/bash
# tests/p10k/make-lang-fixtures.sh DIR : fake tools and projects for the
# language/version-manager segments (segments.sh). Everything is under DIR:
#   bin/      fake commands (rbenv, python, node, go, ...) that print versions
#   home/     *_ROOT directories (global versions, installed versions)
#   proj/     a project with version files; proj/sub is a subdirectory
set -e
D=${1:?usage: make-lang-fixtures.sh DIR}
rm -rf "$D"; mkdir -p "$D"/{bin,home,proj/sub}
fake() { printf '#!/bin/sh\n%s\n' "$2" >"$D/bin/$1"; chmod +x "$D/bin/$1"; }
for t in rbenv goenv nodenv jenv luaenv plenv phpenv scalaenv pyenv rvm-prompt fvm; do fake "$t" 'exit 0'; done
fake python  'echo "Python 3.11.4"'
fake go      'echo "go version go1.21.5 linux/amd64"'
fake php     'printf "PHP 8.3.1 (cli) (built: Jan 1 2024)\nCopyright\n"'
fake java    'echo "openjdk full version \"21.0.1+12-29\"" >&2'
fake dotnet  'echo "8.0.100"'
fake swift   'echo "Swift version 5.9.2 (swift-5.9.2-RELEASE)"'
fake rustc   'echo "rustc 1.74.1 (a28077b28 2023-12-04)"'
fake stack   'case $STACK_YAML in *global-project*) echo ghc-9.2.8 ;; *) echo ghc-9.4.7 ;; esac'
fake node    'echo v20.10.0'

# *_ROOT: global versions
for t in rbenv nodenv jenv luaenv plenv phpenv scalaenv; do mkdir -p "$D/home/.$t"; echo 1.0.0 >"$D/home/.$t/version"; done
mkdir -p "$D/home/.goenv" "$D/home/.pyenv/versions/3.12.1" "$D/home/.nodenv/versions/18.1.0"
echo 'go-1.20.0' >"$D/home/.goenv/version"
echo '3.10.0' >"$D/home/.pyenv/version"

# a project with local versions
cd "$D/proj"
echo '3.2.0' >.ruby-version
printf 'go-1.21.5\n# comment\n\n  1.22.0 extra\n' >.go-version
echo 'node-v18.1.0' >.node-version
echo '21' >.java-version
echo '5.4.6' >.lua-version
echo 'perl-5.38.0' >.perl-version
echo '8.3.0' >.php-version
echo '3.3.1' >.scala-version
printf 'python-3.12.1\n' >.python-version
touch stack.yaml go.mod composer.json Cargo.toml lib.pm
printf '{\n  "name": "demo-pkg",\n  "deps": {"version": "9"},\n  "version": "1.2.3"\n}\n' >package.json
mkdir -p .fvm "$D/home/fvm/versions/3.13.0"
ln -s "$D/home/fvm/versions/3.13.0" .fvm/flutter_sdk

# virtualenvs
mkdir -p "$D/home/work/myproj/venv" "$D/home/cfgenv"
printf 'home = /usr/bin\nprompt = "my env"\n' >"$D/home/cfgenv/pyvenv.cfg"

# nvm: default alias 18 -> v18.19.0 installed; node on PATH is v20.10.0
mkdir -p "$D/home/nvm/alias" "$D/home/nvm/versions/node/v18.19.0/bin" "$D/home/nvm/versions/node/v20.10.0/bin"
echo 18 >"$D/home/nvm/alias/default"
for v in v18.19.0 v20.10.0; do
  printf '#!/bin/sh\necho %s\n' "$v" >"$D/home/nvm/versions/node/$v/bin/node"; chmod +x "$D/home/nvm/versions/node/$v/bin/node"
done
# asdf: plugins nodejs python ruby golang terraform (zsh's key order matters),
# global versions in the fake home, a project overriding two of them
A=$D/home/asdfhome; mkdir -p "$A/.asdf/plugins" "$A/proj/sub"
for p in nodejs python ruby golang terraform; do mkdir -p "$A/.asdf/plugins/$p/bin" "$A/.asdf/installs/$p"; done
mkdir -p "$A/.asdf/installs/nodejs/20.10.0" "$A/.asdf/installs/nodejs/18.19.0" "$A/.asdf/installs/python/3.12.1" \
         "$A/.asdf/installs/ruby/3.3.0" "$A/.asdf/installs/golang/1.21.5" "$A/.asdf/installs/terraform/1.6.6"
printf 'nodejs 18.19.0\npython 3.12.1\nruby 3.3.0\ngolang 1.21.5\nterraform 1.6.6\n' >"$A/.tool-versions"
printf 'nodejs 21.0.0 20.10.0 # picks the installed one\npython system\nruby 3.3.0\nunknown 1.0\n' >"$A/proj/.tool-versions"
printf '#!/bin/sh\nexit 0\n' >"$D/bin/asdf"; chmod +x "$D/bin/asdf"
# cloud: kubectl prints a config chosen by $KUBE_FIX; terraform, gcloud, eb, az
mkdir -p "$D/cloud/kube" "$D/cloud/gcloud/configurations" "$D/cloud/tf/.terraform" "$D/cloud/eb/.elasticbeanstalk" "$D/cloud/azure"
cat >"$D/cloud/kube/plain.yaml" <<'Y'
apiVersion: v1
clusters:
- cluster:
    server: https://1.2.3.4
  name: dev-cluster
contexts:
- context:
    cluster: dev-cluster
    namespace: kube-system
    user: admin
  name: dev
- context:
    cluster: gke_my-account_us-east1-a_cluster-01
    user: gke-user
  name: "gke-ctx"
current-context: dev
kind: Config
Y
sed 's/^current-context: dev$/current-context: "gke-ctx"/' "$D/cloud/kube/plain.yaml" >"$D/cloud/kube/gke.yaml"
printf '#!/bin/sh\ncat "$KUBE_FIX"\n' >"$D/bin/kubectl"; chmod +x "$D/bin/kubectl"
: >"$D/cloud/kube/config"
echo 'staging' >"$D/cloud/tf/.terraform/environment"
echo '1.6.6' >"$D/cloud/tf/.terraform-version"
printf '#!/bin/sh\nprintf "Terraform v1.6.6\\non linux_amd64\\n"\n' >"$D/bin/terraform"; chmod +x "$D/bin/terraform"
: >"$D/cloud/eb/.elasticbeanstalk/config.yml"
printf '#!/bin/sh\nprintf "  app-dev\\n* app-prod\\n"\n' >"$D/bin/eb"; chmod +x "$D/bin/eb"
printf '%s\n' '{"subscriptions":[{"name":"Other","isDefault":false},{"name":"Prod Sub","isDefault":true}]}' >"$D/cloud/azure/azureProfile.json"
printf '#!/bin/sh\nexit 1\n' >"$D/bin/az"; chmod +x "$D/bin/az"
echo work >"$D/cloud/gcloud/active_config"
printf '[core]\naccount = me@example.com\nproject = my-proj\n' >"$D/cloud/gcloud/configurations/config_work"
cat >"$D/bin/gcloud" <<'G'
#!/bin/sh
case "$1 $2" in
  "config configurations") printf 'me@example.com\001my-proj\n' ;;
  "projects describe") echo "My Project" ;;
esac
G
chmod +x "$D/bin/gcloud"
printf '[default]\nregion = eu-west-1\n\n[profile "prod team"]\nregion = us-east-2 # c\n' >"$D/cloud/aws-config"
printf '%s\n' '{"type":"service_account","project_id":"proj-1","client_email":"sa@proj-1.iam"}' >"$D/cloud/gcred.json"
echo "fixtures in $D"
