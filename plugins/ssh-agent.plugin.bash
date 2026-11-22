# about: start one ssh-agent per user and share it between shells (add keys with ssh-add)
# ssh-add -l exits 2 when it cannot reach an agent (0/1: agent there, with/without keys).
_b4h_agent_up() { ssh-add -l >/dev/null 2>&1; (( $? != 2 )); }
if command -v ssh-agent >/dev/null && ! _b4h_agent_up; then
  _b4h_agent_env=${XDG_RUNTIME_DIR:-$HOME/.ssh}/b4h-ssh-agent.env
  [[ -r $_b4h_agent_env ]] && . "$_b4h_agent_env" >/dev/null
  if ! _b4h_agent_up; then
    (umask 077; ssh-agent -s >"$_b4h_agent_env")
    . "$_b4h_agent_env" >/dev/null
  fi
  unset _b4h_agent_env
fi
unset -f _b4h_agent_up
