#!/usr/bin/env bash
# test-menu-space-fix.sh - Menu that accepts Space, Alt+Space (ESC+Space), and fallbacks (x/s)
# Controls:
#  ↑ / ↓ : move
#  Space : toggle selection (normal or ESC+Space)
#  x / s : toggle selection (fallback)
#  Enter : confirm
#  ←     : back (exit code 1)
#  ESC   : cancel (press ESC alone)
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
  echo "ERROR: cannot open /dev/tty. Run the script in an interactive terminal."
  exit 1
fi

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
  printf "%b\n" "${GREEN}│${NC}  Menu - Space toggle fix test            ${GREEN}│${NC}" > /dev/tty
  printf "%b\n" "${GREEN}└────────────────────────────────────────────┘${NC}" > /dev/tty
  printf "\n" > /dev/tty
  printf "%b\n" "${GREEN}Use ↑/↓ to move, Space to toggle, x/s to toggle (fallback), Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
  printf "%b\n" "${CYAN}DEBUG: key hex printed below (helps diagnose odd mappings).${NC}" > /dev/tty
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

  # raw mode for /dev/tty
  stty -echo -icanon time 0 min 0 < /dev/tty 2>/dev/null || true

  # read first byte
  key1=""
  while true; do
    read -rsn1 -u 3 key1 2>/dev/null || true
    if [[ -n "$key1" ]]; then break; fi
    sleep 0.02
  done

  k1hex=$(hex_of_char "$key1" || true)
  printf "%b" "[DEBUG] key1 hex: ${k1hex:-}<empty>\n" > /dev/tty

  if [[ $key1 == $'\x1b' ]]; then
    # On ESC, read additional bytes with slightly longer timeout to capture sequences
    seq_rest=""
    key2=""; key3=""
    # read next byte (longer timeout to catch ESC+Space / Alt+Space)
    read -rsn1 -t 0.15 -u 3 key2 2>/dev/null || true
    if [[ -n "$key2" ]]; then
      k2hex=$(hex_of_char "$key2" || true)
      printf "%b" "[DEBUG] key2 hex: ${k2hex:-}<empty>\n" > /dev/tty
      seq_rest+="$key2"
      # if the second byte is '[' then it's an arrow/seq: read one more with short timeout
      if [[ $key2 == "[" ]]; then
        read -rsn1 -t 0.05 -u 3 key3 2>/dev/null || true
        if [[ -n "$key3" ]]; then
          k3hex=$(hex_of_char "$key3" || true)
          printf "%b" "[DEBUG] key3 hex: ${k3hex:-}<empty>\n" > /dev/tty
          seq_rest+="$key3"
        fi
      fi
    fi

    # Now interpret seq_rest: priority for ESC+Space (Alt+Space), then arrow sequences, then standalone ESC
    if [[ -n "$seq_rest" && "${seq_rest:0:1}" == " " ]]; then
      # ESC + Space (Alt+Space) -> toggle selection
      if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
    elif [[ "$seq_rest" == "["* ]]; then
      # arrow handling (e.g., "[A" / "[B" / "[C" / "[D")
      case "$seq_rest" in
        "[A"*) ((cursor--)); if [[ $cursor -lt 0 ]]; then cursor=$((count-1)); fi ;;
        "[B"*) ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
        "[D"*) # left -> back
          stty "$oldstty" < /dev/tty 2>/dev/null || true
          exec 3<&-
          printf "\nBack pressed (exit code 1)\n" > /dev/tty
          exit 1
          ;;
        "[C"*) ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi ;;
        *) 
          # unknown sequence after ESC: ignore
          ;;
      esac
    else
      # No additional bytes after ESC within timeout -> treat as standalone ESC (exit)
      stty "$oldstty" < /dev/tty 2>/dev/null || true
      exec 3<&-
      printf "\nESC pressed (exit code 2)\n" > /dev/tty
      exit 2
    fi

  else
    # non-escape single key
    k1hex=$(hex_of_char "$key1" || true)
    case "$k1hex" in
      "0A"|"0D") # Enter
        done=1
        ;;
      "20"|"A0") # Space (normal or NBSP)
        if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
        ;;
      "78"|"58"|"73"|"53") # x/X or s/S
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

# final restore
stty "$oldstty" < /dev/tty 2>/dev/null || true
exec 3<&-

# Print selection summary
printf "\nSelected items:\n" > /dev/tty
for ((i=0;i<count;i++)); do
  if [[ ${sel[i]} -eq 1 ]]; then
    key="${items[i]%%|*}"
    label="${items[i]#*|}"
    printf " - %s (%s)\n" "$key" "$label" > /dev/tty
  fi
done

exit 0