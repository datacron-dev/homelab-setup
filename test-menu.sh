#!/usr/bin/env bash
# test-menu-bright.sh - Minimal test for Unicode/ASCII circle checklist UI (bright colors)
# Controls:
#  ↑ / ↓ : move
#  Space : toggle selection
#  Enter : confirm (exit code 0)
#  ←     : back (exit code 1)
#  ESC   : cancel/exit (exit code 2)
#
# Exits with 0 and prints selected keys on success.

set -u

# Bright/regular colors
BRIGHT_GREEN=$'\033[1;32m'
GREEN=$'\033[0;32m'
BRIGHT_WHITE=$'\033[1;37m'
WHITE=$'\033[0;37m'
NC=$'\033[0m'

# Detect UTF-8 for glyphs
CHARMAP=$(locale charmap 2>/dev/null || echo "")
if [[ "$CHARMAP" == "UTF-8" ]]; then
  FILLED="●"
  EMPTY="○"
else
  FILLED="o"
  EMPTY="O"
fi

# Simple items (key|label)
items=(
  "docker|Docker Engine (amd64)"
  "vscode|Visual Studio Code"
  "tailscale|Tailscale VPN"
  "ollama|Ollama (Local LLM Runner)"
)

# Initialize selection array
declare -a sel
for ((i=0;i<${#items[@]};i++)); do sel[i]=0; done

# Prepare /dev/tty for input
exec 3</dev/tty

# Save stty state (explicitly read from /dev/tty)
oldstty=$(stty -g < /dev/tty 2>/dev/null || true)

cleanup() {
  # restore stty to /dev/tty if we captured one
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
      # Focused: bold white filled symbol + bold white label
      printf "%b " "${BRIGHT_WHITE}${FILLED}${NC}" > /dev/tty
      printf "%b\n" "${BRIGHT_WHITE}${label}${NC}" > /dev/tty
    else
      if [[ ${sel[i]} -eq 1 ]]; then
        # Selected but not-focused: BRIGHT GREEN filled circle + bright-green label
        printf "%b " "${BRIGHT_GREEN}${FILLED}${NC}" > /dev/tty
        printf "%b\n" "${BRIGHT_GREEN}${label}${NC}" > /dev/tty
      else
        # Not selected: GREEN empty circle + green label
        printf "%b " "${GREEN}${EMPTY}${NC}" > /dev/tty
        printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
      fi
    fi
  done

  # Read key from /dev/tty, and configure stty on /dev/tty
  stty -echo -icanon time 0 min 0 < /dev/tty 2>/dev/null || true
  key1=""
  while true; do
    read -rsn1 -u 3 key1 2>/dev/null || true
    if [[ -n "$key1" ]]; then break; fi
    sleep 0.02
  done

  if [[ $key1 == $'\x1b' ]]; then
    # maybe arrow sequence
    read -rsn1 -t 0.01 -u 3 key2 2>/dev/null || true
    read -rsn1 -t 0.01 -u 3 key3 2>/dev/null || true
    seq="$key2$key3"
    case "$seq" in
      "[A") ((cursor--)); if [[ $cursor -lt 0 ]]; then cursor=$((count-1)); fi ;;
      "[B") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      "[D") # left -> back
        # restore stty and exit with code 1
        stty "$oldstty" < /dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nBack pressed (exit code 1)\n" > /dev/tty
        exit 1
        ;;
      "[C") ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
      *) # standalone ESC
        stty "$oldstty" < /dev/tty 2>/dev/null || true
        exec 3<&-
        printf "\nESC pressed (exit code 2)\n" > /dev/tty
        exit 2
        ;;
    esac
  elif [[ $key1 == $'\x0a' || $key1 == $'\x0d' ]]; then
    # Enter -> confirm
    done=1
  elif [[ $key1 == " " ]]; then
    # toggle selection
    if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
  fi

  # ensure stty restored to old settings in case loop continues
  stty "$oldstty" < /dev/tty 2>/dev/null || true
done

# Final restore (cleanup trap will run)
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