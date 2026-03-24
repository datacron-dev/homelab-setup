#!/usr/bin/env bash
# test-menu-debug-space.sh - Debug menu w/ robust space handling + fallbacks
# Controls:
#  ↑ / ↓ : move
#  Space : toggle selection (accepted: 0x20, 0xA0)
#  x / s : toggle selection (fallback)
#  Enter : confirm (exit code 0)
#  ←     : back (exit code 1)
#  ESC   : cancel/exit (exit code 2)
set -u

# Colors
BRIGHT_GREEN=$'\033[1;32m'
GREEN=$'\033[0;32m'
BRIGHT_WHITE=$'\033[1;37m'
WHITE=$'\033[0;37m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# Glyphs
CHARMAP=$(locale charmap 2>/dev/null || echo "")
if [[ "$CHARMAP" == "UTF-8" ]]; then
  FILLED="●"
  EMPTY="○"
else
  FILLED="o"
  EMPTY="O"
fi

# Menu items
items=(
  "docker|Docker Engine (amd64)"
  "vscode|Visual Studio Code"
  "tailscale|Tailscale VPN"
  "ollama|Ollama (Local LLM Runner)"
)

# selection array
declare -a sel
for ((i=0;i<${#items[@]};i++)); do sel[i]=0; done

# open /dev/tty on fd 3
if ! exec 3</dev/tty 2>/dev/null; then
  echo "ERROR: cannot open /dev/tty. Run the script in an interactive terminal (not a backgrounded/non-tty stdin)."
  exit 1
fi

# save stty for /dev/tty
oldstty=$(stty -g < /dev/tty 2>/dev/null || true)

cleanup() {
  if [[ -n "$oldstty" ]]; then
    stty "$oldstty" < /dev/tty 2>/dev/null || true
  fi
  exec 3<&- || true
  printf "%b" "$NC" > /dev/tty
}
trap cleanup RETURN INT TERM

# helper: hex bytes of char
hex_of_char() {
  local ch="$1"
  printf "%s" "$ch" | od -An -t x1 | tr -s ' ' | sed 's/^ //' | tr '[:lower:]' '[:upper:]'
}

cursor=0
count=${#items[@]}
done=0

while [[ $done -eq 0 ]]; do
  # draw UI
  printf "\033[H\033[2J" > /dev/tty
  printf "%b\n" "${GREEN}┌────────────────────────────────────────────┐${NC}" > /dev/tty
  printf "%b\n" "${GREEN}│${NC}  Debug Menu - Space handling test        ${GREEN}│${NC}" > /dev/tty
  printf "%b\n" "${GREEN}└────────────────────────────────────────────┘${NC}" > /dev/tty
  printf "\n" > /dev/tty
  printf "%b\n" "${GREEN}Use ↑/↓ to move, Space to toggle, x/s to toggle (fallback), Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
  printf "%b\n" "${CYAN}DEBUG: Key hex codes will be shown below.${NC}" > /dev/tty
  printf "\n" > /dev/tty

  for ((i=0;i<count;i++)); do
    pair="${items[i]}"
    label="${pair#*|}"
    if [[ $i -eq $cursor ]]; then
      printf "%b " "${BRIGHT_WHITE}${FILLED}${NC}" > /dev/tty
      printf "%b\n" "${BRIGHT_WHITE}${label}${NC}" > /dev/tty
    else
      if [[ ${sel[i]} -eq 1 ]]; then
        printf "%b " "${BRIGHT_GREEN}${FILLED}${NC}" > /dev/tty
        printf "%b\n" "${BRIGHT_GREEN}${label}${NC}" > /dev/tty
      else
        printf "%b " "${GREEN}${EMPTY}${NC}" > /dev/tty
        printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
      fi
    fi
  done

  # set raw mode on /dev/tty for immediate reads
  stty -echo -icanon time 0 min 0 < /dev/tty 2>/dev/null || true

  # read first byte from /dev/tty via fd 3
  key1=""
  while true; do
    read -rsn1 -u 3 key1 2>/dev/null || true
    if [[ -n "$key1" ]]; then break; fi
    sleep 0.02
  done

  # show debug hex for key1
  k1hex=$(hex_of_char "$key1" || true)
  printf "%b" "[DEBUG] key1 hex: ${k1hex:-}<empty>\n" > /dev/tty

  if [[ $key1 == $'\x1b' ]]; then
    # possible arrow sequence; read remainder with short timeout
    key2=""; key3=""
    read -rsn1 -t 0.05 -u 3 key2 2>/dev/null || true
    read -rsn1 -t 0.05 -u 3 key3 2>/dev/null || true
    k2hex=$(hex_of_char "$key2" || true)
    k3hex=$(hex_of_char "$key3" || true)
    printf "%b" "[DEBUG] key2 hex: ${k2hex:-}<empty> key3 hex: ${k3hex:-}<empty>\n" > /dev/tty

    seq="$key2$key3"
    case "$seq" in
      "[A") ((cursor--)); if [[ $cursor -lt 0 ]]; then cursor=$((count-1)); fi ;;
      "[B") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      "[D")
        stty "$oldstty" < /dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nBack pressed (exit code 1)\n" > /dev/tty
        exit 1
        ;;
      "[C") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      *) # standalone ESC
        stty "$oldstty" < /dev/tty 2>/dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nESC pressed (exit code 2)\n" > /dev/tty
        exit 2
        ;;
    esac

  else
    # non-escape single key handling
    # get hex again (safe)
    k1hex=$(hex_of_char "$key1" || true)
    # handle common forms of space and fallback keys
    case "$k1hex" in
      "0A"|"0D") # Enter
        done=1
        ;;
      "20"|"A0") # normal space or NBSP
        if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
        ;;
      "78"|"58"|"73"|"53") # x/X (78/58) or s/S (73/53) hex values
        if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
        ;;
      *)
        printf "%b" "[DEBUG] Unhandled key hex ${k1hex} - ignored\n" > /dev/tty
        ;;
    esac
  fi

  # restore stty for next iteration
  stty "$oldstty" < /dev/tty 2>/dev/null || true
done

# final restore via trap
stty "$oldstty" < /dev/tty 2>/dev/null || true
exec 3<&-

# print selection summary
printf "\nSelected items:\n" > /dev/tty
for ((i=0;i<count;i++)); do
  if [[ ${sel[i]} -eq 1 ]]; then
    key="${items[i]%%|*}"
    label="${items[i]#*|}"
    printf " - %s (%s)\n" "$key" "$label" > /dev/tty
  fi
done

exit 0