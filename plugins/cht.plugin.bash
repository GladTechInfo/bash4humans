# about: cht TOPIC [QUERY] - cheat sheets from cht.sh (e.g. cht tar, cht bash read file)
cht() {
  (( $# )) || { echo 'usage: cht TOPIC [QUERY...]  e.g. cht tar   cht bash loop over files' >&2; return 2; }
  local topic=$1; shift
  local q=${*// /+}
  curl -fsS "https://cht.sh/$topic${q:+/$q}" | "${PAGER:-less}"
}
