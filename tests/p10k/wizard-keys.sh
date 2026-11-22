# tests/p10k/wizard-keys.sh : sourced. wizard_keys KEY=VALUE... -> REPLY, the
# keys that answer p10k's configuration wizard, one character per question,
# following the wizard's own conditions (internal/wizard.zsh). Defaults give a
# nerdfont-v3 terminal, 256 colours.
#   font: diamond=y|n lock=y|n arrow=y|n width=1|2|3 lock2=y|n arrow2=y|n
#         python=y|n quotes=y|n        (the font questions and their order)
#   style=lean|classic|rainbow|pure  charset=1|2  colors=1|2 (lean; pure when
#   TRUECOLOR=1)  color=1-4 (classic)  rprompt=1|2 (pure)  time=n|1|2
#   sep=1-4  head=1-5  tail=1-5  lines=1|2  gap=1-3  frame=1-4  orn=1-4
#   spacing=1|2  icons=1|2  flow=1|2  transient=y|n  padding=y|n  instant=1|2|3
#   zshrc=y|n|'' (asked only when the rc file lacks the lines)
wizard_keys() {
  local -A a=([diamond]=y [lock]=y [arrow]=y [width]=1 [lock2]=y [arrow2]=y [python]=y [quotes]=y
              [style]=rainbow [charset]=1 [colors]=1 [color]=1 [rprompt]=1 [time]=n [sep]=1 [head]=1
              [tail]=1 [lines]=2 [gap]=1 [frame]=1 [orn]=1 [spacing]=1 [icons]=1 [flow]=1
              [transient]=n [padding]=y [instant]=1 [zshrc]='')
  local kv k='' mode
  for kv in "$@"; do a[${kv%%=*}]=${kv#*=}; done
  # font: wizard.zsh main loop
  local diamond=0 lock=0 arrow=0 python=0
  k+=${a[diamond]}; [[ ${a[diamond]} == y ]] && diamond=1
  k+=${a[lock]}
  if [[ ${a[lock]} == y ]]; then
    if (( ! diamond )); then mode=awesome-fontconfig
    else
      k+=${a[arrow]}; [[ ${a[arrow]} == y ]] && arrow=1
      if (( arrow )); then k+=${a[width]}; [[ ${a[width]} == 1 ]] || arrow=0; fi
      if (( arrow )); then mode=nerdfont-v3
      else
        k+=${a[arrow2]}
        if [[ ${a[arrow2]} == y ]]; then mode=nerdfont-complete
        else mode=awesome-fontconfig; k+=${a[python]}; [[ ${a[python]} == y ]] && python=1
        fi
      fi
    fi
  else
    k+=${a[lock2]}
    if [[ ${a[lock2]} == y ]]; then
      if (( diamond )); then mode=awesome-patched; k+=${a[python]}; else mode=flat; fi
    else
      if (( diamond )); then mode=powerline
      else k+=${a[quotes]}; [[ ${a[quotes]} == y ]] && mode=compatible || mode=ascii
      fi
    fi
  fi
  [[ $mode == @(powerline|compatible|ascii) ]] || k+=${a[padding]}
  # fewer than 256 colours (COLORS8=1): no style question, lean_8colors
  # (ask_style), and no colour question either (ask_color_scheme)
  if [[ ${COLORS8-} == 1 ]]; then a[style]=lean
  else
    case ${a[style]} in lean) k+=1 ;; classic) k+=2 ;; rainbow) k+=3 ;; pure) k+=4 ;; esac
  fi
  local ascii=0; [[ $mode == ascii ]] && ascii=1
  if [[ ${a[style]} != pure ]] && (( ! ascii )); then k+=${a[charset]}; [[ ${a[charset]} == 2 ]] && ascii=1; fi
  [[ ${a[style]} == lean && ${COLORS8-} != 1 ]] && k+=${a[colors]}
  [[ ${a[style]} == pure && ${TRUECOLOR-} == 1 ]] && k+=${a[colors]}
  [[ ${a[style]} == classic ]] && k+=${a[color]}
  [[ ${a[style]} == pure ]] && k+=${a[rprompt]}
  k+=${a[time]}
  if [[ ${a[style]} == classic || ${a[style]} == rainbow ]]; then
    (( diamond && ! ascii )) && k+=${a[sep]}
    if (( ! ascii )); then
      local nh=${a[head]} nt=${a[tail]}
      k+=$nh k+=$nt
    fi
  fi
  k+=${a[lines]}
  local gapch=1 frame=1
  if [[ ${a[lines]} == 2 && ${a[style]} != pure ]]; then k+=${a[gap]}; gapch=${a[gap]}; fi
  if [[ ${a[lines]} == 2 && ${a[style]} != pure ]] && (( ! ascii )); then k+=${a[frame]}; frame=${a[frame]}; fi
  # ornaments (ask_ornaments_color): rainbow/lean*, 2 lines, and a gap
  # character or a frame. Frames exist only if the frame question was asked
  # (not ascii) and answered other than 1 (no frame).
  if [[ ${a[lines]} == 2 && ( ${a[style]} == rainbow || ${a[style]} == lean ) ]]; then
    local frames=0
    (( ! ascii )) && [[ $frame != 1 ]] && frames=1
    if (( gapch != 1 || frames )); then k+=${a[orn]}; fi
  fi
  k+=${a[spacing]}
  if [[ ${a[style]} != pure && $mode != @(powerline|compatible) ]] && (( ! ascii )); then k+=${a[icons]}; fi
  [[ ${a[style]} != pure ]] && k+=${a[flow]}
  k+=${a[transient]}
  k+=${a[instant]}
  k+=${a[zshrc]}
  REPLY=$k
}
