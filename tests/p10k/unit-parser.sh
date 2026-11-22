#!/bin/bash
# tests/p10k/unit-parser.sh : p10k's _p9k_parse_buffer (real p10k in zsh)
# against the port, on a corpus of command lines (tests/p10k/parser-corpus.txt,
# one line per case; a literal \n inside a line stands for a newline).
# The lines are only parsed, never run. Compares P9K_COMMANDS.
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
corpus=$root/tests/p10k/parser-corpus.txt
pass=0 fail=0
while IFS= read -r line; do
  [[ -z $line || $line == '#'* ]] && continue
  line=${line//\\n/$'\n'}
  z=$(EDITOR=vim zsh -fc 'source ~/src/powerlevel10k/powerlevel10k.zsh-theme
    setopt interactive_comments
    alias k=kubectl s="sudo " g="git" ll="ls -l"
    _p9k_parse_buffer "$1" 64
    local -a c=("${(@)P9K_COMMANDS//$'"'"'\0'"'"'/,}"); print -rn -- "${(j:|:)c}"' x "$line" 2>&1 </dev/null)
  b=$(EDITOR=vim bash -c '. "'"$root"'/lib/p10k/main.bash"; . "'"$root"'/lib/p10k/parser.bash"
    alias k=kubectl s="sudo " g="git" ll="ls -l"
    _p9k_parse_buffer "$1" 64
    IFS="|"; x="${P9K_COMMANDS[*]}"; printf "%s" "${x//$'"'"'\x1f'"'"'/,}"' x "$line" 2>&1 </dev/null)
  # p10k's quirk for "$NAME": the command is the shell's process id ($$),
  # which differs between the two shells by nature; compare as "a number"
  [[ $z =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] && z=PID b=PID
  if [[ $z == "$b" ]]; then (( pass++ )); [[ -n ${V-} ]] && echo "SAME  ${line//$'\n'/⏎}  ->  $z"
  else (( fail++ )); echo "DIFF  ${line//$'\n'/⏎}"; echo "   zsh:  $z"; echo "   bash: $b"; fi
done <"$corpus"
echo "same: $pass   different: $fail"
