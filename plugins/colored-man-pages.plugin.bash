# about: manual pages in colour (headings, options, the search line)
man() {
  LESS_TERMCAP_md=$'\e[1;36m' LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_us=$'\e[4;32m' LESS_TERMCAP_ue=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[1;30;43m' LESS_TERMCAP_se=$'\e[0m' \
  GROFF_NO_SGR=1 MANROFFOPT=-c command man "$@"
}
