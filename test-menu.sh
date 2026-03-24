#!/usr/bin/env bash
# test-menu.sh - Minimal test for Unicode/ASCII circle checklist UI
# Controls:
#  ↑ / ↓ : move
#  Space : toggle selection
#  Enter : confirm (exit code 0)
#  ←     : back (exit code 1)
#  ESC   : cancel/exit (exit code 2)
#
# Exits with 0 and prints selected keys on success.

set -u

# Colors (safe defaults)
GREEN='\033[0;32m'
WHITE='\033[0;37m'
NC='\033[0m'

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

# Save stty and ensure restore
oldstty=$(stty -g)
cleanup() {
  stty "$oldstty"
  exec 3<&-
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
      # Focused: white filled symbol + white label
      printf "%b " "${WHITE}${FILLED}${NC}" > /dev/tty
      printf "%b\n" "${WHITE}${label}${NC}" > /dev/tty
    else
      if [[ ${sel[i]} -eq 1 ]]; then
        printf "%b " "${GREEN}${FILLED}${NC}" > /dev/tty
        printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
      else
        printf "%b " "${GREEN}${EMPTY}${NC}" > /dev/tty
        printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
      fi
    fi
  done

  # Read key
  stty -echo -icanon time 0 min 0
  key1=""
  while true; do
    read -rsn1 -u 3