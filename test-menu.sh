#!/usr/bin/env bash
# test-menu-debug.sh - Debug menu to inspect key codes (space toggle troubleshooting)
# Controls:
#  ↑ / ↓ : move
#  Space : toggle selection
#  Enter : confirm (exit code 0)
#  ←     : back (exit code 1)
#  ESC   : cancel/exit (exit code 2)
#
# This script prints debug info (hex codes) for keys to help diagnose why Space
# may not be detected in your terminal environment.
set -u

# Colors
BRIGHT_GREEN=$'\033[1;32m'
GREEN=$'\033[0;32m'
BRIGHT_WHITE=$'\033[1;37m'
WHITE=$'\033[0;37m'
NC=$'\033[0m'

# Glyphs (UTF-8 preferred)
CHARMAP=$(locale charmap 2>/dev/null || echo "")
if [[ "$CHARMAP" == "UTF-8" ]]; then
  FILLED="●"
  EMPTY="○"
else
  FILLED="o"
  EMPTY="O"
fi

# Menu items (key|label)
items=(
  "docker|Docker Engine (amd64)"
  "vscode|Visual Studio Code"
  "tailscale|Tailscale VPN"
  "ollama|Ollama (Local LLM Runner)"
)

# Selection array
declare -a sel
for ((i=0;i<${#items[@]};i++)); do sel[i]=0; done

# Try to open /dev/tty for interactive input (fd 3)
if ! exec 3</dev/tty 2>/dev/null; then
  echo "ERROR: Cannot open /dev/tty. Running this via a non-interactive stdin (curl | bash) may not work."
  echo "Please download the file and run it in a terminal, or run via WSL/Git Bash/ssh shell."
  exit 1
fi

# Save current terminal settings for /dev/tty
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
  printf "%b\n" "${GREEN}│${NC}  Debug Menu - Use arrows / Space / Enter  ${GREEN}│${NC}" > /dev/tty
  printf "%b\n" "${GREEN}└────────────────────────────────────────────┘${NC}" > /dev/tty
  printf "\n" > /dev/tty
  printf "%b\n" "${GREEN}Use ↑/↓ to move, Space to toggle, Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
  printf "%b\n" "${GREEN}DEBUG: The script will print key hex codes for each keypress below.${NC}" > /dev/tty
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

  # Put /dev/tty in raw/non-canonical mode for immediate reads
  stty -echo -icanon time 0 min 0 < /dev/tty 2>/dev/null || true

  # Read first byte from /dev/tty via fd 3
  key1=""
  while true; do
    read -rsn1 -u 3 key1 2>/dev/null || true
    if [[ -n "$key1" ]]; then break; fi
    sleep 0.02
  done

  # Helper to print hex of a char (safe)
  hex_of_char() {
    local ch="$1"
    # Use od to print bytes in hex; trim whitespace
    printf "%s" "$ch" | od -An -t x1 | tr -s ' ' | sed 's/^ //' | tr '[:lower:]' '[:upper:]'
  }

  # Debug: print what we received for key1
  k1hex=$(hex_of_char "$key1" || true)
  printf "%b" "${CYAN:-}\n[DEBUG] key1 raw: '"
  printf "%b" "$key1"
  printf "%b" "'  hex: ${k1hex}\n${NC}" > /dev/tty

  # If Escape, read additional bytes to capture arrow sequences
  if [[ $key1 == $'\x1b' ]]; then
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
    # Non-escape single key: print hex and act
    k1hex=$(hex_of_char "$key1" || true)
    printf "%b" "[DEBUG] single-key hex: ${k1hex}\n" > /dev/tty

    case "$k1hex" in
      "0A"|"0D") # newline / Enter (LF/CR)
        done=1
        ;;
      "20") # space (0x20)
        if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
        ;;
      *)
        # Some terminals may send different codes for space; show debug and ignore
        printf "%b" "[DEBUG] Unhandled key hex ${k1hex} (ignored)\n" > /dev/tty
        ;;
    esac
  fi

  # restore terminal mode for next loop
  stty "$oldstty" < /dev/tty 2>/dev/null || true
done

# Final restore via cleanup trap
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
