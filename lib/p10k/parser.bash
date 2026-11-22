# =============================================================================
#  lib/p10k/parser.bash - p10k's command-line parser (internal/parser.zsh):
#  _p9k_parse_buffer BUFFER [TOKEN_LIMIT] -> P9K_COMMANDS, the commands the
#  line would run (after aliases, through sudo/nice/env-style precommands,
#  pipelines, lists, substitutions). SHOW_ON_COMMAND uses it.
#
#  Two parts: _p9k_pb_lex splits the line into tokens the way zsh's ${(Z+C+)}
#  does (comments dropped: bash's interactive_comments is on by default), and
#  _p9k_parse_buffer is the state machine of parser.zsh, statement by
#  statement. zsh patterns are written as bash regular expressions.
# =============================================================================

# words that are not commands; value: what to skip until (regex), if anything
declare -gA _p9k_pb_cmd_skip=(
  ['}']='always' ['{']='' ['|']='' ['||']='' ['&']='' ['&&']='' ['|&']='' ['&!']='' ['&|']=''
  [')']='' ['(']='' ['()']='' ['!']='' [';']='' [if]='' [fi]='' [elif]='' [else]='' [then]=''
  [while]='' [until]='' [do]='' [done]='' [esac]='' [end]='' [coproc]='' [nocorrect]=''
  [noglob]='' [time]='' ['[[']='^\]\]$' ['((']='^\)\)$' [case]='^(\)|esac)$'
  [';;']='^(\)|esac)$' [';&']='^(\)|esac)$' [';|']='^(\)|esac)$' [foreach]='^\(.*\)$'
)
# precommands; value: options that take an argument (regex)
declare -gA _p9k_pb_precommand=(
  [-]='' [builtin]='' [command]='' [exec]='^-[^a]*[a]$' [nohup]='' [setsid]='' [eatmydata]=''
  [catchsegv]='' [pkexec]='^--user$' [doas]='^-[^aCu]*[acU]$' [nice]='^(-[^n]*[n]|--adjustment)$'
  [stdbuf]='^(-[^ioe]*[ioe]|--(input|output|error))$'
  [sudo]='^(-[^aghpuUCcrtT]*[aghpuUCcrtT]|--(close-from|group|host|prompt|role|type|other-user|command-timeout|user))$'
  [ssh-agent]='^-[^aEPt]*[aEPt]$' [tabbed]='^-[^gnprtTuU]*[gnprtTuU]$' [chronic]='' [ifne]=''
)
declare -gA _p9k_pb_redirect=(
  ['&>']='' ['>']='' ['>&']='' ['<']='' ['<&']='' ['<>']='' ['&>|']='' ['>|']='' ['&>>']=''
  ['>>']='' ['>>&']='' ['&>>|']='' ['>>|']='' ['<<<']=''
)
declare -gA _p9k_pb_term=(
  ['|']='' ['||']='' [';']='' ['&']='' ['&&']='' ['|&']='' ['&!']='' ['&|']='' [';;']=''
  [';&']='' [';|']='' ['(']='' [')']='' ['()']='' ['}']=''
)
declare -gA _p9k_pb_term_skip=(['(']='^\)$' [';;']='^(\)|esac)$' [';&']='^(\)|esac)$' [';|']='^(\)|esac)$')

# ----------------------------------------------------------------- lexer ---
# Read a balanced construct starting at $i (opening at s[i]); appends to w,
# advances i past the closing character. Handles quotes inside.
_p9k_pb_balanced() {   # OPEN CLOSE
  local o=$1 cl=$2 depth=0 ch
  while (( i < n )); do
    ch=${s:i:1}
    case $ch in
      \\) w+=${s:i:2}; (( i += 2 )); continue ;;
      \') if [[ $o != \' ]]; then local j=${s:i+1}; j=${j%%\'*}; w+="'$j'"; (( i += ${#j} + 2 )); continue; fi ;;
      \") if [[ $o != \" ]]; then _p9k_pb_dq; continue; fi ;;
    esac
    w+=$ch; (( i++ ))
    if [[ $ch == "$o" ]]; then (( depth++ ))
    elif [[ $ch == "$cl" ]]; then (( --depth == 0 )) && return 0
    fi
  done
}
# a double-quoted string starting at $i
_p9k_pb_dq() {
  local ch
  w+='"'; (( i++ ))
  while (( i < n )); do
    ch=${s:i:1}
    case $ch in
      \\) w+=${s:i:2}; (( i += 2 )) ;;
      \") w+='"'; (( i++ )); return 0 ;;
      \$) if [[ ${s:i+1:1} == '(' ]]; then w+='$'; (( i++ )); _p9k_pb_balanced '(' ')'
          elif [[ ${s:i+1:1} == '{' ]]; then w+='$'; (( i++ )); _p9k_pb_balanced '{' '}'
          else w+=$ch; (( i++ )); fi ;;
      \`) local j=${s:i+1}; j=${j%%\`*}; w+="\`$j\`"; (( i += ${#j} + 2 )) ;;
      *) w+=$ch; (( i++ )) ;;
    esac
  done
}

# _p9k_pb_lex STRING -> _p9k__tok (array of tokens)
_p9k_pb_lex() {
  local s=$1 n=${#1} i=0 ch w op
  _p9k__tok=()
  local -a ops=('&>>|' '>>&|' '&>>' '>>&' '>>|' '&>|' '>&|' '<<<' '<<-' '<<' '>>' '&>' '>&' '<&' '<>' '>|'
                '||' '&&' '|&' '&!' '&|' ';;' ';&' ';|' '|' '&' ';' '<' '>' '(' ')')
  while (( i < n )); do
    ch=${s:i:1}
    case $ch in
      ' '|$'\t') (( i++ )); continue ;;
      $'\n') _p9k__tok+=(';'); (( i++ )); continue ;;
      '#') while (( i < n )) && [[ ${s:i:1} != $'\n' ]]; do (( i++ )); done; continue ;;
    esac
    # (( ... )) at the start of a word: one token
    if [[ ${s:i:2} == '((' ]]; then
      w=''; _p9k_pb_balanced '(' ')'
      _p9k__tok+=("$w"); continue
    fi
    if [[ ${s:i:2} == '()' ]]; then _p9k__tok+=('()'); (( i += 2 )); continue; fi
    # an operator (an fd number may come first: 2> 2>&)
    w=''
    if [[ ${s:i} =~ ^[0-9]+[\<\>] ]]; then
      local num=${s:i}; num=${num%%[!0-9]*}; w=$num; (( i += ${#num} ))
    fi
    for op in "${ops[@]}"; do
      if [[ ${s:i:${#op}} == "$op" ]]; then
        # <( and >( start a process substitution, i.e. a word
        if [[ ( $op == '<' || $op == '>' ) && ${s:i+1:1} == '(' && -z $w ]]; then break; fi
        _p9k__tok+=("$w$op"); (( i += ${#op} )); continue 2
      fi
    done
    [[ -n $w ]] && { (( i -= ${#w} )); w=''; }
    # a word
    while (( i < n )); do
      ch=${s:i:1}
      case $ch in
        ' '|$'\t'|$'\n'|';'|'&'|'|') break ;;
        '<'|'>')
          if [[ ${s:i+1:1} == '(' ]]; then w+=$ch; (( i++ )); _p9k_pb_balanced '(' ')'; continue; fi
          break ;;
        '(')
          # arr=( ... ), =( ... ), x( ... ) glob qualifiers: part of the word;
          # but "f()" is the word f and the token ()
          if [[ -n $w && ${s:i+1:1} != ')' ]]; then _p9k_pb_balanced '(' ')'; continue; fi
          break ;;
        ')') break ;;
        \\) w+=${s:i:2}; (( i += 2 )) ;;
        \') local j=${s:i+1}; j=${j%%\'*}; w+="'$j'"; (( i += ${#j} + 2 )) ;;
        \") _p9k_pb_dq ;;
        \`) local j=${s:i+1}; j=${j%%\`*}; w+="\`$j\`"; (( i += ${#j} + 2 )) ;;
        \$)
          case ${s:i+1:1} in
            '(') w+='$'; (( i++ )); _p9k_pb_balanced '(' ')' ;;
            '{') w+='$'; (( i++ )); _p9k_pb_balanced '{' '}' ;;
            \') w+='$'; (( i++ )); local j=${s:i+1}
                # $'...' with backslash escapes
                local k=0; while (( k < ${#j} )); do [[ ${j:k:1} == \\ ]] && { (( k += 2 )); continue; }; [[ ${j:k:1} == \' ]] && break; (( k++ )); done
                w+="'${j:0:k}'"; (( i += k + 2 )) ;;
            *) w+=$ch; (( i++ )) ;;
          esac ;;
        *) w+=$ch; (( i++ )) ;;
      esac
    done
    [[ -n $w ]] && _p9k__tok+=("$w")
  done
}

# zsh ${(Q)TOKEN}, also for $'...' -> _p9k__ret
_p9k_pb_unq() {
  if [[ $1 == \$\'*\' ]]; then printf -v _p9k__ret '%b' "${1:2:${#1}-3}"; return; fi
  _p9k_unquote "$1"
}

# ------------------------------------------------------------------ parser ---
_p9k_parse_buffer() {
  local limit=${2:-0}
  [[ $limit =~ ^[0-9]+$ ]] || return 2
  P9K_COMMANDS=()
  local id='([0-9]+|[[:alpha:]_][[:alnum:]_]*)'
  local var="^(\\\$$id|\\\$\\{$id\\}|\"\\\$$id\"|\"\\\$\\{$id\\}\")\$"
  local -i e c
  if (( limit )); then c=$limit; else c=$(( 1 << 62 )); fi
  local skip='' n s r state='' token cmd='' prev=''
  local -a aln=() alp=() alf=() v=() tokens
  _p9k_pb_lex "$1"; tokens=("${_p9k__tok[@]}")
  local ret=0
  while (( ${#tokens[@]} )); do
    e=${#state}
    while (( ${#alp[@]} )) && (( ${#tokens[@]} == alp[-1] )); do
      unset 'aln[-1]' 'alp[-1]'
      if (( ${#alf[@]} )) && (( ${#tokens[@]} == alf[-1] )); then unset 'alf[-1]'; e=0; fi
    done
    while :; do
      if (( c-- <= 0 )); then ret=1; break 2; fi
      token=${tokens[0]}; tokens=("${tokens[@]:1}")
      if (( e )); then break
      elif [[ -n ${BASH_ALIASES[$token]+x} ]]; then
        local x seen=0; for x in "${aln[@]}"; do [[ $x == "p$token" ]] && seen=1; done
        (( seen )) && break
        s=${BASH_ALIASES[$token]} n=p$token
      else
        break
      fi
      aln+=("$n") alp+=(${#tokens[@]})
      [[ $s == *' ' ]] && alf+=(${#tokens[@]})
      _p9k_pb_lex "$s"; tokens=("${_p9k__tok[@]}" "${tokens[@]}")
    done

    case $token in
      '<<'|'<<-') state=h; continue ;;
    esac
    # command and process substitutions: their commands are parsed too
    if [[ $token == *'`'* || $token =~ [\<\>=\$]\( ]]; then
      if [[ $token =~ ^(\`[^\`]+\`|\"\`[^\`]+\`\"|\$\([^\)]+\)|\"\$\([^\)]+\)\"|[\<\>=]\([^\)]+\))$ ]]; then
        s=$token
        [[ $s == \"*\" ]] && s=${s:1:${#s}-2}
        [[ $s == [\$\<\>=]* ]] && s=${s:1}
        s=${s:1:${#s}-2}
        _p9k_pb_lex "$s"; tokens+=(';' "${_p9k__tok[@]}")
      fi
    fi

    local fall=0
    case $state in
      *r) state=${state%?}; continue ;;
      a)
        if [[ $token =~ ^($skip)$ ]]; then
          if [[ $token == '{' ]]; then
            P9K_COMMANDS+=("$cmd"); cmd='' state=''
          else
            skip='\{'
          fi
          continue
        else
          state=t
        fi
        fall=1 ;;
    esac
    if (( fall )) || [[ $state == t || $state == p* ]]; then
      if [[ -n ${_p9k_pb_term[$token]+x} ]]; then
        if [[ $token == '()' ]]; then
          state=''
        else
          P9K_COMMANDS+=("$cmd")
          if [[ $token == '}' ]]; then
            state=a skip=always
          else
            skip=${_p9k_pb_term_skip[$token]}
            [[ -n $skip ]] && state=s || state=''
          fi
        fi
        cmd=''
        continue
      elif [[ $state == t ]]; then
        continue
      elif [[ $state == *x ]]; then
        if [[ -n ${_p9k_pb_redirect[$token]+x} ]]; then
          prev='' state=${state%?}r
          continue
        else
          state=${state%?}
        fi
      fi
    elif [[ $state == s ]]; then
      [[ $token =~ $skip ]] && state=''
      continue
    elif [[ $state == h ]]; then
      # skip the here-document: up to a line that is just the delimiter
      _p9k_pb_unq "$token"; local delim=$_p9k__ret k
      while (( ${#tokens[@]} )); do
        k=-1
        for (( e = 0; e < ${#tokens[@]}; e++ )); do [[ ${tokens[e]} == "$delim" ]] && { k=$e; break; }; done
        if (( k < 0 )); then tokens=(); break; fi
        if (( k >= 1 )) && [[ ${tokens[k-1]} == ';' && ${tokens[k+1]-} == ';' ]]; then
          tokens=("${tokens[@]:k+1}"); break
        else
          tokens=("${tokens[@]:k+1}")
        fi
      done
      while (( ${#alp[@]} )) && (( alp[-1] >= ${#tokens[@]} )); do unset 'aln[-1]' 'alp[-1]'; done
      state=t
      continue
    fi

    # a redirection (with an fd number): the next word is its target
    r=${token#"${token%%[!0-9]*}"}
    if [[ -n $r && -n ${_p9k_pb_redirect[$r]+x} ]]; then
      state+=r
      continue
    fi

    # $var: replaced by its value (split into words unless quoted)
    if [[ $token == *'$'* && $token =~ $var ]]; then
      # p10k takes the name as the token minus its first and last non-name
      # character, which works only for $NAME: for "$NAME" and "${NAME}" the
      # name keeps a "$" and zsh reads it as $$ (the shell's process id); for
      # ${NAME} it is "{NAME", which has no value. Reproduced as is.
      if [[ $token == \"* ]]; then v=("$$")
      elif [[ $token == \$\{* ]]; then v=()
      else n=${token#?}; read -r -a v <<<"${!n-}"
      fi
      # zsh ${(@qq)v}: each word in single quotes
      local q=() x; for x in "${v[@]}"; do q+=("'${x//\'/\'\\\'\'}'"); done
      tokens=("${q[@]}" "${tokens[@]}")
      continue
    fi

    case $state in
      '')
        if [[ -n ${_p9k_pb_cmd_skip[$token]+x} ]]; then
          skip=${_p9k_pb_cmd_skip[$token]}
          if [[ $token == '}' ]]; then state=a; elif [[ -n $skip ]]; then state=s; else state=''; fi
          continue
        fi
        if [[ $token == *=* ]]; then
          # an assignment NAME=, NAME+=, NAME[...]=, N=
          if [[ $token =~ ^([0-9]+|[[:alpha:]_][[:alnum:]_]*(\[.*[^\\](\\\\)*\])?)\+?=(.*)$ ]]; then
            [[ ${BASH_REMATCH[4]} == '(' ]] && { state=s; skip='^\)$'; }
            continue
          fi
        fi
        _p9k_pb_unq "$token"; token=$_p9k__ret ;;
      p2|p|p1)
        local st=$state
        if [[ $st == p2 ]]; then
          if [[ -n $prev ]]; then prev=''; st=p
          else
            _p9k_pb_unq "$token"; token=$_p9k__ret
            if [[ $token =~ ^\{$id\}$ ]]; then state=p2x prev=$token; else state=p; fi
            continue
          fi
        fi
        if [[ $st == p ]]; then
          if [[ -n $prev ]]; then token=$prev prev=''
          else
            _p9k_pb_unq "$token"; token=$_p9k__ret
            if [[ $token =~ ^\{$id\}$ ]]; then prev=$token state=px; continue
            elif [[ -n $token && $token != -* ]]; then :
            elif [[ $token == -- ]]; then state=p1; continue
            elif [[ -n $skip && $token =~ $skip ]]; then state=p2; continue
            else continue
            fi
          fi
        elif [[ $st == p1 ]]; then
          if [[ -n $prev ]]; then token=$prev prev=''
          else
            _p9k_pb_unq "$token"; token=$_p9k__ret
            if [[ $token =~ ^\{$id\}$ ]]; then state=p1x prev=$token; continue; fi
          fi
        fi ;;
    esac

    if [[ -n ${_p9k_pb_precommand[$token]+x} ]]; then
      prev='' state=p skip=${_p9k_pb_precommand[$token]}
      cmd+=$token$'\x1f'
    else
      state=t
      [[ $token == '(('*'))' || $token == '`'*'`' || $token == '$'* || $token =~ ^[\<\>=]\(.*\)$ || $token == *$'\x1f'* ]] || cmd+=$token$'\x1f'
    fi
  done
  [[ $state == px || $state == p1x ]] && cmd+=$prev
  P9K_COMMANDS+=("$cmd")
  # strip the trailing separator, drop duplicates (zsh ${(u)...}) and empties
  local -a out=(); local x y dup
  for x in "${P9K_COMMANDS[@]}"; do
    x=${x%$'\x1f'}
    [[ -n $x ]] || continue
    dup=0; for y in "${out[@]}"; do [[ $y == "$x" ]] && dup=1; done
    (( dup )) || out+=("$x")
  done
  P9K_COMMANDS=("${out[@]}")
  return $ret
}
