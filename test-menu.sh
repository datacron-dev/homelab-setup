#!/usr/bin/env bash
# test-menu-fixed-space.sh - Minimal UI with robust key handling (space toggle fix)
set -u

BRIGHT_GREEN=$'\033[1;32m'
GREEN=$'\033[0;32m'
BRIGHT_WHITE=$'\033[1;37m'
WHITE=$'\033[0;37m'
NC=$'\033[0m'

CHARMAP=$(locale charmap 2>/dev/null || echo "")
if [[ "$CHARMAP" == "UTF-8" ]]; then
  FILLED="●"
  EMPTY="○"
else
  FILLED="o"
  EMPTY="O"
fi

items=(
  "docker|Docker Engine (amd64)"
  "vscode|Visual Studio Code"
  "tailscale|Tailscale VPN"
  "ollama|Ollama (Local LLM Runner)"
)

declare -a sel
for ((i=0;i<${#items[@]};i++)); do sel[i]=0; done

# open /dev/tty for input on fd 3
exec 3</dev/tty

# Save stty for /dev/tty
oldstty=$(stty -g < /dev/tty 2>/dev/null || true)

cleanup() {
  if [[ -n "$oldstty" ]]; then
    stty "$oldstty" < /dev/tty 2>/dev/null || true
  fi
  exec 3<&- || true
  printf "%b" "$NC" > /dev/tty
}
trap cleanup RETURN INT TERM

cursor=0
count=${#items[@]}
done=0

while [[ $done -eq 0 ]]; do
  # Draw UI
  printf "\033[H\033[2J" > /dev/tty
  printf "%b\n" "${GREEN}┌────────────────────────────────────────────┐${NC}" > /dev/tty
  printf "%b\n" "${GREEN}│${NC}  Test Menu - Use arrows / Space / Enter   ${GREEN}│${NC}" > /dev/tty
  printf "%b\n" "${GREEN}└────────────────────────────────────────────┘${NC}" > /dev/tty
  printf "\n" > /dev/tty
  printf "%b\n" "${GREEN}Use ↑/↓ to move, Space to toggle, Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
  printf "\n" > /dev/tty

  for ((i=0;i<count;i++)); do
    pair="${items[i]}"
    key="${pair%%|*}"
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

  # Put tty in non-canonical mode for immediate single-char reads
  stty -echo -icanon time 0 min 0 < /dev/tty 2>/dev/null || true

  # Read first byte from /dev/tty (fd 3)
  key1=""
  while true; do
    read -rsn1 -u 3 key1 2>/dev/null || true
    if [[ -n "$key1" ]]; then break; fi
    sleep 0.02
  done

  # If Escape, read next bytes to detect arrows; otherwise handle single-key actions
  if [[ $key1 == $'\x1b' ]]; then
    # read the rest of the sequence (short timeout)
    key2=""; key3=""
    read -rsn1 -t 0.02 -u 3 key2 2>/dev/null || true
    read -rsn1 -t 0.02 -u 3 key3 2>/dev/null || true
    seq="$key2$key3"
    case "$seq" in
      "[A") ((cursor--)); if [[ $cursor -lt 0 ]]; then cursor=$((count-1)); fi ;;
      "[B") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      "[D") # left -> back
        stty "$oldstty" < /dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nBack pressed (exit code 1)\n" > /dev/tty
        exit 1
        ;;
      "[C") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      *) # standalone ESC -> exit
        stty "$oldstty" < /dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nESC pressed (exit code 2)\n" > /dev/tty
        exit 2
        ;;
    esac
  else
    # Single-key handling (space, enter)
    case "$key1" in
      $'\x0a'|$'\x0d') # Enter (LF or CR)
        done=1
        ;;
      ' ' | $'\x20') # Space (explicit)
        if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
        ;;
      *) 
        # ignore other keys
        ;;
    esac
  fi

  # restore canonical stty for next iteration (we saved oldstty)
  stty "$oldstty" < /dev/tty 2>/dev/null || true
done

# Final restore (trap will also run)
stty "$oldstty" < /dev/tty 2>/dev/null || true
exec 3<&-

# Print selections
printf "\nSelected items:\n" > /dev/tty
for ((i=0;i<count;i++)); do
  if [[ ${sel[i]} -eq 1 ]]; then
    key="${items[i]%%|*}"
    label="${items[i]#*|}"
    printf " - %s (%s)\n" "$key" "$label" > /dev/tty
  fi
done

exit 0
