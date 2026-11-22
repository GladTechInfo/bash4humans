# =============================================================================
#  lib/p10k/expand.bash - bash versions of zsh-only expressions found in p10k
#  templates. The converter (b4h-tool p10k-config) writes them as
#  ${$((_p9k_x_NAME()))+${_p9k_x}}; _p9k_expand calls the function, which sets
#  _p9k_x. Each comment shows the zsh original.
# =============================================================================

# ${${${${CONDA_PROMPT_MODIFIER#\(}% }%\)}:-${CONDA_PREFIX:t}}
_p9k_x_anaconda() {
  local m=${CONDA_PROMPT_MODIFIER-}
  m=${m#\(}; m=${m% }; m=${m%\)}
  if [[ -n $m ]]; then _p9k_x=$m; else _p9k_x=${CONDA_PREFIX##*/}; fi
}

# ${P9K_CONTENT}${${P9K_CONTENT:#$P9K_PYENV_PYTHON_VERSION(|/*)}:+ $P9K_PYENV_PYTHON_VERSION}
_p9k_x_pyenv() {
  _p9k_x=$P9K_CONTENT
  local v=${P9K_PYENV_PYTHON_VERSION-}
  if [[ -n $P9K_CONTENT && $P9K_CONTENT != "$v" && $P9K_CONTENT != "$v"/* ]]; then _p9k_x+=" $v"; fi
}

# ${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+…}
_p9k_x_timewarrior() {
  _p9k_x=${P9K_CONTENT:0:24}
  [[ -n ${P9K_CONTENT:24} ]] && _p9k_x+=…
}

# ${P9K_TOOLBOX_NAME:#fedora-toolbox-*}
_p9k_x_toolbox() {
  _p9k_x=${P9K_TOOLBOX_NAME-}
  [[ $_p9k_x == fedora-toolbox-* ]] && _p9k_x=''
}

# ${${${P9K_CONTENT/⇣* :⇡/⇣⇡}// }//:/ }
_p9k_x_pure_vcs() {
  local c=$P9K_CONTENT
  if [[ $c == *'⇣'*' :⇡'* ]]; then
    local pre=${c%%⇣*} rest=${c#*⇣}
    rest=${rest#* :⇡}
    c="${pre}⇣⇡$rest"
  fi
  c=${c// /}
  _p9k_x=${c//:/ }
}

# ${${:-/$P9K_KUBECONTEXT_NAMESPACE}:#/default}
_p9k_x_kube_namespace() {
  _p9k_x=/${P9K_KUBECONTEXT_NAMESPACE-}
  [[ $_p9k_x == /default ]] && _p9k_x=''
}

# ${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+..}   (ASCII configs)
_p9k_x_timewarrior_ascii() {
  _p9k_x=${P9K_CONTENT:0:24}
  [[ -n ${P9K_CONTENT:24} ]] && _p9k_x+=..
}
