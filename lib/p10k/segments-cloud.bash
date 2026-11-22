# =============================================================================
#  lib/p10k/segments-cloud.bash - cloud segments: aws, aws_eb_env, azure,
#  gcloud, google_app_cred, kubecontext, terraform, terraform_version,
#  docker_machine. Ports of the same-named p10k functions.
# =============================================================================

# ------------------------------------------------------------- stat cache ---
# p10k: _p9k_cache_stat_get LABEL FILE... / _p9k_cache_stat_set VALUE...
# A result is reused while the files keep their inode, modification time,
# size and mode. Values come back in _p9k__cache_val (index 1 = first, as in
# zsh; index 0 unused).
declare -gA _p9k__stat_cache=()
_p9k_cache_stat_get() {
  local label=$1; shift
  _p9k__cache_stat_key=$label$'\1'"$*"
  _p9k__cache_stat_meta=''
  (( $# )) && _p9k__cache_stat_meta=$(stat -L -c '%n %i %Y %s %f' -- "$@" 2>/dev/null)
  local c=${_p9k__stat_cache[$_p9k__cache_stat_key]-}
  [[ -n $c && ${c%%$'\2'*} == "$_p9k__cache_stat_meta" ]] || return 1
  eval "${c#*$'\2'}"
  return 0
}
_p9k_cache_stat_set() {
  _p9k__cache_val=('' "$@")
  _p9k__stat_cache[$_p9k__cache_stat_key]=$_p9k__cache_stat_meta$'\2'$(declare -p _p9k__cache_val)
}

# p10k's *_CLASSES: (PATTERN CLASS PATTERN CLASS ...) -> _p9k__ret "_CLASS"
# for the first zsh pattern that matches $2 (array name in $1).
_p9k_class_state() {
  local -n _cl=$1
  local i pat
  _p9k__ret=''
  for (( i = 0; i + 1 < ${#_cl[@]}; i += 2 )); do
    pat=${_cl[i]//(/@(}
    # shellcheck disable=SC2053
    if [[ $2 == $pat ]]; then
      [[ -n ${_cl[i+1]} ]] && _p9k__ret=_${_cl[i+1]^^}
      break
    fi
  done
}

# ---------------------------------------------------------------------- aws ---
# The profile, with P9K_AWS_REGION from AWS_REGION / AWS_DEFAULT_REGION or
# the profile's "region =" in the AWS config file.
_p9k_parse_aws_config() {
  _p9k__aws_regions=()
  [[ -f $1 && -r $1 ]] || return 0
  local line profile=''
  local re_def='^[[:space:]]*\[default\][[:space:]]*(#.*)?$'
  # (p10k's patterns allow no blanks inside the name or the region)
  local re_prof='^\[profile[[:space:]]+([^[:space:]]+)[[:space:]]*\][[:space:]]*(#.*)?$'
  local re_reg='^[[:space:]]*region[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$'
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $re_def ]]; then
      profile=default
    elif [[ $line =~ $re_prof ]]; then
      # zsh ${(Q)...}: quotes removed (never evaluated)
      _p9k_unquote "${BASH_REMATCH[1]}"; profile=$_p9k__ret
    elif [[ $line =~ $re_reg ]]; then
      if [[ -n $profile ]]; then
        _p9k__aws_regions+=("${#profile}:$profile:${BASH_REMATCH[1]}")
        profile=''
      fi
    fi
  done <"$1"
}
prompt_aws() {
  P9K_AWS_PROFILE=${AWS_SSO_PROFILE:-${AWS_VAULT:-${AWSUME_PROFILE:-${AWS_PROFILE:-${AWS_DEFAULT_PROFILE-}}}}}
  _p9k_class_state _POWERLEVEL9K_AWS_CLASSES "$P9K_AWS_PROFILE"; local state=$_p9k__ret
  if [[ -n ${AWS_REGION:-${AWS_DEFAULT_REGION-}} ]]; then
    P9K_AWS_REGION=${AWS_REGION:-$AWS_DEFAULT_REGION}
  else
    local cfg=${AWS_CONFIG_FILE:-$HOME/.aws/config}
    if ! _p9k_cache_stat_get prompt_aws "$cfg"; then
      _p9k_parse_aws_config "$cfg"
      _p9k_cache_stat_set "${_p9k__aws_regions[@]}"
    fi
    local prefix=${#P9K_AWS_PROFILE}:$P9K_AWS_PROFILE: kv='' x
    for x in "${_p9k__cache_val[@]:1}"; do [[ $x == "$prefix"* ]] && { kv=$x; break; }; done
    P9K_AWS_REGION=${kv#"$prefix"}
  fi
  _p9k_prompt_segment "prompt_aws$state" red white AWS_ICON 0 '' "${P9K_AWS_PROFILE//%/%%}"
}
_p9k_prompt_aws_init() {
  _p9k_set_cond '${AWS_SSO_PROFILE:-${AWS_VAULT:-${AWSUME_PROFILE:-${AWS_PROFILE:-${AWS_DEFAULT_PROFILE-}}}}}'
}

# --------------------------------------------------------------- aws_eb_env ---
# The environment marked "* " in `eb list`, inside an Elastic Beanstalk project.
prompt_aws_eb_env() {
  _p9k_upglob .elasticbeanstalk -/ && return 0
  local dir=${_p9k__parent_dirs[$?]}
  if ! _p9k_cache_stat_get prompt_aws_eb_env "$dir/.elasticbeanstalk/config.yml"; then
    local env='' line
    while IFS= read -r line; do [[ $line == '* '* ]] && env+=${env:+ }${line#\* }; done < <(command eb list 2>/dev/null)
    _p9k_cache_stat_set "$env"
  fi
  [[ -n ${_p9k__cache_val[1]} ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" black green AWS_EB_ICON 0 '' "${_p9k__cache_val[1]//%/%%}"
}
_p9k_prompt_aws_eb_env_init() { _p9k_set_cond '@_p9k_have_cmd eb'; }

# -------------------------------------------------------------------- azure ---
prompt_azure() {
  local name cfg=${AZURE_CONFIG_DIR:-$HOME/.azure}/azureProfile.json
  if _p9k_cache_stat_get prompt_azure "$cfg"; then
    name=${_p9k__cache_val[1]}
  else
    if type -P jq >/dev/null && name=$(jq -r '[.subscriptions[]|select(.isDefault==true)|.name][]|strings' "$cfg" 2>/dev/null); then
      name=${name%%$'\n'*}
    elif ! name=$(az account show --query name --output tsv 2>/dev/null); then
      name=''
    fi
    _p9k_cache_stat_set "$name"
  fi
  [[ -n $name ]] || return 0
  _p9k_class_state _POWERLEVEL9K_AZURE_CLASSES "$name"
  _p9k_prompt_segment "prompt_azure$_p9k__ret" blue white AZURE_ICON 0 '' "${name//%/%%}"
}
_p9k_prompt_azure_init() { _p9k_set_cond '@_p9k_have_cmd az'; }

# ----------------------------------------------------------- docker_machine ---
prompt_docker_machine() { _p9k_prompt_segment "${FUNCNAME[0]}" magenta "$_p9k_color1" SERVER_ICON 0 '' "${DOCKER_MACHINE_NAME//%/%%}"; }
_p9k_prompt_docker_machine_init() { _p9k_set_cond '${DOCKER_MACHINE_NAME-}'; }

# ---------------------------------------------------------------- terraform ---
# The workspace: TF_WORKSPACE, or the word in .terraform/environment.
prompt_terraform() {
  local ws=${TF_WORKSPACE-}
  if [[ -z $ws ]]; then
    local f; f=$(realpath -m -- "${TF_DATA_DIR:-.terraform}" 2>/dev/null)/environment
    _p9k_read_word "$f" && ws=$_p9k__ret
  fi
  [[ -z $ws || $ws == default && $_POWERLEVEL9K_TERRAFORM_SHOW_DEFAULT == 0 ]] && return 0
  _p9k_class_state _POWERLEVEL9K_TERRAFORM_CLASSES "$ws"
  _p9k_prompt_segment "prompt_terraform$_p9k__ret" "$_p9k_color1" blue TERRAFORM_ICON 0 '' "$ws"
}
_p9k_prompt_terraform_init() { _p9k_set_cond '@_p9k_have_cmd terraform'; }

prompt_terraform_version() {
  local v cfg='' tf; tf=$(type -P terraform) || return 0
  local tenv_cfg=${TENV_ROOT:-$HOME/.tenv}/Terraform/version
  _p9k_upglob .terraform-version -.; local i=$?
  (( i )) && cfg=${_p9k__parent_dirs[i]}/.terraform-version
  if _p9k_cache_stat_get "prompt_terraform_version.${TFENV_TERRAFORM_VERSION-}" "$tf" $cfg "$tenv_cfg"; then
    v=${_p9k__cache_val[1]}
  else
    v=$(terraform --version 2>/dev/null) || v=''
    v=${v#Terraform v}; v=${v%%$'\n'*}
    _p9k_cache_stat_set "$v"
  fi
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" blue TERRAFORM_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_terraform_version_init() { _p9k_set_cond '@_p9k_have_cmd terraform'; }

# ---------------------------------------------------------- google_app_cred ---
prompt_google_app_cred() {
  unset P9K_GOOGLE_APP_CRED_TYPE P9K_GOOGLE_APP_CRED_PROJECT_ID P9K_GOOGLE_APP_CRED_CLIENT_EMAIL
  if ! _p9k_cache_stat_get prompt_google_app_cred "$GOOGLE_APPLICATION_CREDENTIALS"; then
    local -a lines=()
    local q='[.type//"", .project_id//"", .client_email//"", 0][]'
    if mapfile -t lines < <(jq -r "$q" <"$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null) && (( ${#lines[@]} == 4 )); then
      local IFS=:; local text="${lines[*]:0:3}"; unset IFS
      _p9k_class_state _POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES "$text"
      _p9k_cache_stat_set 1 "${lines[@]:0:3}" "$text" "$_p9k__ret"
    else
      _p9k_cache_stat_set 0
    fi
  fi
  (( ${_p9k__cache_val[1]} )) || return 0
  P9K_GOOGLE_APP_CRED_TYPE=${_p9k__cache_val[2]}
  P9K_GOOGLE_APP_CRED_PROJECT_ID=${_p9k__cache_val[3]}
  P9K_GOOGLE_APP_CRED_CLIENT_EMAIL=${_p9k__cache_val[4]}
  _p9k_prompt_segment "prompt_google_app_cred${_p9k__cache_val[6]}" blue white GCLOUD_ICON 0 '' "${_p9k__cache_val[5]}"
}
_p9k_prompt_google_app_cred_init() { _p9k_set_cond '@_p9k_gac_cond'; }
_p9k_gac_cond() { [[ -n ${GOOGLE_APPLICATION_CREDENTIALS-} ]] && type -P jq >/dev/null; }

# -------------------------------------------------------------- kubecontext ---
# From `kubectl config view -o=yaml`: the current context, then its cluster,
# namespace and user (searched upwards from the context's "  name:" line).
# GKE and EKS cluster names are split into cloud account, zone and cluster.
_p9k_kube_unq() { [[ $1 == \"*\" ]] && _p9k__ret=${1:1:${#1}-2} || _p9k__ret=$1; }
prompt_kubecontext() {
  local IFS=:; local -a cfgs=(${KUBECONFIG:-$HOME/.kube/config}); unset IFS
  if ! _p9k_cache_stat_get prompt_kubecontext "${cfgs[@]}"; then
    local name='' namespace='' cluster='' user='' cloud_name='' cloud_account='' cloud_zone='' cloud_cluster='' text='' state=''
    local str='([^"'\''|>]*|".*")'    # p10k: ([^"'|>]*|"*")
    local -a cfg=()
    if mapfile -t cfg < <(kubectl config view -o=yaml 2>/dev/null); then
      local -a ctx=(); local l
      for l in "${cfg[@]}"; do [[ $l =~ ^current-context:\ $str$ ]] && ctx+=("$l"); done
      if (( ${#ctx[@]} == 1 )); then
        name=${ctx[0]#current-context: }
        local i pos=-1
        for (( i = 0; i < ${#cfg[@]}; i++ )); do [[ ${cfg[i]} == contexts: ]] && { pos=$i; break; }; done
        if (( pos >= 0 )); then
          local start=$(( pos + 1 )) np=-1
          for (( i = start; i < ${#cfg[@]}; i++ )); do [[ ${cfg[i]} == "  name: $name" ]] && { np=$i; break; }; done
          if (( np >= 0 )); then
            for (( i = np - 1; i >= start; i-- )); do
              l=${cfg[i]}
              if [[ $l == '- context:' ]]; then break
              elif [[ $l =~ ^\ \ \ \ cluster:\ ($str)$ ]]; then _p9k_kube_unq "${BASH_REMATCH[1]}"; cluster=$_p9k__ret
              elif [[ $l =~ ^\ \ \ \ namespace:\ ($str)$ ]]; then _p9k_kube_unq "${BASH_REMATCH[1]}"; namespace=$_p9k__ret
              elif [[ $l =~ ^\ \ \ \ user:\ ($str)$ ]]; then _p9k_kube_unq "${BASH_REMATCH[1]}"; user=$_p9k__ret
              fi
            done
          fi
        fi
        _p9k_kube_unq "$name"; name=$_p9k__ret
      fi
    fi
    if [[ -n $name ]]; then
      : "${namespace:=default}"
      local gke='^gke_(.+)_(asia|australia|europe|northamerica|southamerica|us)-([a-z]+[0-9]+)(-[a-z]|)_(.+)$'
      local eks='^arn:aws[[:alnum:]-]*:eks:([[:alnum:]-]+):([[:digit:]]+):cluster/(.+)$'
      local sh=" ${_POWERLEVEL9K_KUBECONTEXT_SHORTEN[*]} "
      if [[ $cluster =~ $gke ]]; then
        cloud_name=gke cloud_account=${BASH_REMATCH[1]}
        cloud_zone=${BASH_REMATCH[2]}-${BASH_REMATCH[3]}${BASH_REMATCH[4]} cloud_cluster=${BASH_REMATCH[5]}
        [[ $sh == *' gke '* ]] && text=$cloud_cluster
      elif [[ $cluster =~ $eks ]]; then
        cloud_name=eks cloud_zone=${BASH_REMATCH[1]} cloud_account=${BASH_REMATCH[2]} cloud_cluster=${BASH_REMATCH[3]}
        [[ $sh == *' eks '* ]] && text=$cloud_cluster
      fi
      if [[ -z $text ]]; then
        text=$name
        if [[ $_POWERLEVEL9K_KUBECONTEXT_SHOW_DEFAULT_NAMESPACE == 1 || ( $namespace != default && $namespace != "$name" ) ]]; then
          text+=/$namespace
        fi
      fi
      _p9k_class_state _POWERLEVEL9K_KUBECONTEXT_CLASSES "$text"; state=$_p9k__ret
    fi
    # zsh ${(g::)...}: echo-style escapes are processed
    local v; local -a out=()
    for v in "$name" "$namespace" "$cluster" "$user" "$cloud_name" "$cloud_account" "$cloud_zone" "$cloud_cluster" "$text"; do
      printf -v v '%b' "$v"; out+=("$v")
    done
    _p9k_cache_stat_set "${out[@]}" "$state"
  fi
  P9K_KUBECONTEXT_NAME=${_p9k__cache_val[1]}
  P9K_KUBECONTEXT_NAMESPACE=${_p9k__cache_val[2]}
  P9K_KUBECONTEXT_CLUSTER=${_p9k__cache_val[3]}
  P9K_KUBECONTEXT_USER=${_p9k__cache_val[4]}
  P9K_KUBECONTEXT_CLOUD_NAME=${_p9k__cache_val[5]}
  P9K_KUBECONTEXT_CLOUD_ACCOUNT=${_p9k__cache_val[6]}
  P9K_KUBECONTEXT_CLOUD_ZONE=${_p9k__cache_val[7]}
  P9K_KUBECONTEXT_CLOUD_CLUSTER=${_p9k__cache_val[8]}
  [[ -n ${_p9k__cache_val[9]} ]] || return 0
  _p9k_prompt_segment "prompt_kubecontext${_p9k__cache_val[10]}" magenta white KUBERNETES_ICON 0 '' "${_p9k__cache_val[9]//%/%%}"
}
_p9k_prompt_kubecontext_init() { _p9k_set_cond '@_p9k_have_cmd kubectl'; }

# ------------------------------------------------------------------- gcloud ---
# Account and project id from the active configuration (cached by file); the
# project's name needs a network call, so a detached background process
# fetches it, at most every GCLOUD_REFRESH_PROJECT_NAME_SECONDS. Until it is
# known the segment shows its PARTIAL state.
prompt_gcloud() {
  # PARTIAL: while the name is unknown (p10k: account and id, if the name is empty)
  _p9k_prompt_segment prompt_gcloud_PARTIAL blue white GCLOUD_ICON 1 \
    '${_p9k__gcloud_partial-}' \
    '${P9K_GCLOUD_ACCOUNT//\%/%%}:${P9K_GCLOUD_PROJECT_ID//\%/%%}'
  _p9k_prompt_segment prompt_gcloud_COMPLETE blue white GCLOUD_ICON 1 \
    '${P9K_GCLOUD_PROJECT_NAME-}' \
    '${P9K_GCLOUD_ACCOUNT//\%/%%}:${P9K_GCLOUD_PROJECT_ID//\%/%%}'
}
_p9k_prompt_gcloud_init() {
  _p9k_set_cond '@_p9k_have_cmd gcloud'
  _p9k__gcloud_file=${XDG_RUNTIME_DIR:-/tmp}/p9k-gcloud.$UID.$$
  [[ " ${_p9k__precompute[*]} " == *' _p9k_gcloud_prefetch '* ]] || _p9k__precompute+=(_p9k_gcloud_prefetch)
}
_p9k_gcloud_prefetch() {
  _p9k_gcloud_prefetch2
  [[ -z ${P9K_GCLOUD_PROJECT_NAME-} ]] && _p9k__gcloud_partial=${P9K_GCLOUD_ACCOUNT-}${P9K_GCLOUD_PROJECT_ID-}
  return 0
}
_p9k_gcloud_prefetch2() {
  _p9k__gcloud_partial=''
  unset P9K_GCLOUD_CONFIGURATION P9K_GCLOUD_ACCOUNT P9K_GCLOUD_PROJECT P9K_GCLOUD_PROJECT_ID P9K_GCLOUD_PROJECT_NAME
  type -P gcloud >/dev/null || return 0
  local dir=${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}
  _p9k_read_word "$dir/active_config" || return 0
  P9K_GCLOUD_CONFIGURATION=$_p9k__ret
  if ! _p9k_cache_stat_get _p9k_gcloud_prefetch "$dir/configurations/config_$P9K_GCLOUD_CONFIGURATION"; then
    local pair account='' project_id=''
    if pair=$(gcloud config configurations describe "$P9K_GCLOUD_CONFIGURATION" --quiet \
         --format=$'value[separator="\1"](properties.core.account,properties.core.project)' </dev/null); then
      IFS=$'\1' read -r account project_id <<<"$pair"
    fi
    _p9k_cache_stat_set "$account" "$project_id"
  fi
  [[ -n ${_p9k__cache_val[1]} ]] && P9K_GCLOUD_ACCOUNT=${_p9k__cache_val[1]}
  if [[ -n ${_p9k__cache_val[2]} ]]; then
    P9K_GCLOUD_PROJECT_ID=${_p9k__cache_val[2]}
    P9K_GCLOUD_PROJECT=$P9K_GCLOUD_PROJECT_ID   # deprecated name, kept as p10k does
  fi
  _p9k__gcloud_partial=''
  _p9k_gcloud_take   # a name fetched in the background?
  local now=${EPOCHREALTIME%[.,]*}
  if [[ ${P9K_GCLOUD_CONFIGURATION-} == "${_p9k_gcloud_configuration-}" &&
        ${P9K_GCLOUD_ACCOUNT-} == "${_p9k_gcloud_account-}" &&
        ${P9K_GCLOUD_PROJECT_ID-} == "${_p9k_gcloud_project_id-}" ]]; then
    [[ -n ${_p9k_gcloud_project_name-} ]] && P9K_GCLOUD_PROJECT_NAME=$_p9k_gcloud_project_name
    local r=${_POWERLEVEL9K_GCLOUD_REFRESH_PROJECT_NAME_SECONDS%%.*}
    if (( r < 0 || ${_p9k__gcloud_last_fetch:-0} + r > now )); then return 0; fi
  else
    _p9k_gcloud_configuration=${P9K_GCLOUD_CONFIGURATION-}
    _p9k_gcloud_account=${P9K_GCLOUD_ACCOUNT-}
    _p9k_gcloud_project_id=${P9K_GCLOUD_PROJECT_ID-}
    _p9k_gcloud_project_name=''
  fi
  [[ -n ${P9K_GCLOUD_CONFIGURATION-} && -n ${P9K_GCLOUD_ACCOUNT-} && -n ${P9K_GCLOUD_PROJECT_ID-} ]] || return 0
  (( ${_p9k__gcloud_busy:-0} )) && return 0
  _p9k__gcloud_last_fetch=$now _p9k__gcloud_busy=1
  local key=$P9K_GCLOUD_CONFIGURATION$'\2'$P9K_GCLOUD_ACCOUNT$'\2'$P9K_GCLOUD_PROJECT_ID f=$_p9k__gcloud_file
  ( {
      n=$(gcloud projects describe "$P9K_GCLOUD_PROJECT_ID" --configuration="$P9K_GCLOUD_CONFIGURATION" \
            --account="$P9K_GCLOUD_ACCOUNT" --format='value(name)' 2>/dev/null </dev/null)
      printf '%s\1%s' "$key" "$n" >"$f.tmp" && mv -f -- "$f.tmp" "$f"
    } >/dev/null 2>&1 & )
  # ble.sh: redraw the prompt on the screen when the name comes (p10k:
  # _p9k_prompt_gcloud_update from its worker); plain bash: at the next prompt.
  if (( ${_p9k_ble:-0} && ! ${_p9k__gcloud_watch:-0} )); then
    _p9k__gcloud_watch=1
    ble/util/idle.push -F "$f" _p9k_gcloud_idle
  fi
}

# A fetched name for the current configuration -> _p9k_gcloud_project_name.
_p9k_gcloud_take() {
  [[ -s $_p9k__gcloud_file ]] || return 1
  local got; got=$(<"$_p9k__gcloud_file"); rm -f -- "$_p9k__gcloud_file"
  [[ ${got%%$'\1'*} == "${_p9k_gcloud_configuration-}"$'\2'"${_p9k_gcloud_account-}"$'\2'"${_p9k_gcloud_project_id-}" ]] &&
    _p9k_gcloud_project_name=${got#*$'\1'}
  _p9k__gcloud_busy=0
  return 0
}

# ble.sh idle task (p10k: _p9k_prompt_gcloud_update): the name came while the
# prompt is shown; if it belongs to the shown configuration, redraw.
_p9k_gcloud_idle() {
  _p9k__gcloud_watch=0
  _p9k_gcloud_take || return 0
  [[ ${P9K_GCLOUD_CONFIGURATION-} == "${_p9k_gcloud_configuration-}" &&
     ${P9K_GCLOUD_ACCOUNT-} == "${_p9k_gcloud_account-}" &&
     ${P9K_GCLOUD_PROJECT_ID-} == "${_p9k_gcloud_project_id-}" &&
     ${_p9k_gcloud_project_name-} != "${P9K_GCLOUD_PROJECT_NAME-}" ]] || return 0
  if [[ -n ${_p9k_gcloud_project_name-} ]]; then
    P9K_GCLOUD_PROJECT_NAME=$_p9k_gcloud_project_name _p9k__gcloud_partial=''
  else
    unset P9K_GCLOUD_PROJECT_NAME
    _p9k__gcloud_partial=${P9K_GCLOUD_ACCOUNT-}${P9K_GCLOUD_PROJECT_ID-}
  fi
  _p9k_replay_render
}
