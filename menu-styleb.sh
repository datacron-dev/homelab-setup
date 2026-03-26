lets attempt style b. 

Lets update the test-menu.sh file below. 

#!/usr/bin/env bash
# test-menu-circle-only-highlight.sh
# Menu that highlights only the circle while keeping labels green.
# Accepts: Space (normal or ESC+Space), x/s fallback, arrow keys, Enter, ESC.
set -u

# Colors
BRIGHT_GREEN=$'\033[1;32m'
GREEN=$'\033[0;32m'
BRIGHT_WHITE=$'\033[1;37m'
NC=$'\033[0m'
CYAN=$'\033[0;36m'

# Glyphs (Style B: filled/empty square with arrow cursor)
CHARMAP=$(locale charmap 2>/dev/null || echo "")
if [[ "$CHARMAP" == "UTF-8" ]]; then
  FILLED="■"
  EMPTY="□"
  CURSOR="▶"
else
  FILLED="x"
  EMPTY="-"
  CURSOR=">"
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
  printf "%b\n" "${GREEN}│${NC}  Menu - Style B: Square + Arrow cursor    ${GREEN}│${NC}" > /dev/tty
  printf "%b\n" "${GREEN}└────────────────────────────────────────────┘${NC}" > /dev/tty
  printf "\n" > /dev/tty
  printf "%b\n" "${GREEN}Use ↑/↓ to move, Space/x/s to toggle, Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
  printf "%b\n" "${CYAN}DEBUG: key hex printed below.${NC}" > /dev/tty
  printf "\n" > /dev/tty

  for ((i=0;i<count;i++)); do
    pair="${items[i]}"
    label="${pair#*|}"

    if [[ $i -eq $cursor ]]; then
      # Focused row: white arrow cursor + white square (selected) or white empty square
      if [[ ${sel[i]} -eq 1 ]]; then
        printf "%b %b %b\n" "${BRIGHT_WHITE}${CURSOR}${NC}" "${BRIGHT_WHITE}${FILLED}${NC}" "${GREEN}${label}${NC}" > /dev/tty
      else
        printf "%b %b %b\n" "${BRIGHT_WHITE}${CURSOR}${NC}" "${BRIGHT_WHITE}${EMPTY}${NC}" "${GREEN}${label}${NC}" > /dev/tty
      fi
    else
      if [[ ${sel[i]} -eq 1 ]]; then
        # Selected & unfocused: no arrow, bright green filled square, green label
        printf "  %b %b\n" "${BRIGHT_GREEN}${FILLED}${NC}" "${GREEN}${label}${NC}" > /dev/tty
      else
        # Unselected & unfocused: no arrow, green empty square, green label
        printf "  %b %b\n" "${GREEN}${EMPTY}${NC}" "${GREEN}${label}${NC}" > /dev/tty
      fi
    fi
  done

  # raw mode on /dev/tty
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
    # read additional bytes (longer timeout for ESC+Space)
    seq_rest=""
    key2=""; key3=""
    read -rsn1 -t 0.15 -u 3 key2 2>/dev/null || true
    if [[ -n "$key2" ]]; then
      k2hex=$(hex_of_char "$key2" || true)
      printf "%b" "[DEBUG] key2 hex: ${k2hex:-}<empty>\n" > /dev/tty
      seq_rest+="$key2"
      if [[ $key2 == "[" ]]; then
        read -rsn1 -t 0.05 -u 3 key3 2>/dev/null || true
        if [[ -n "$key3" ]]; then
          k3hex=$(hex_of_char "$key3" || true)
          printf "%b" "[DEBUG] key3 hex: ${k3hex:-}<empty>\n" > /dev/tty
          seq_rest+="$key3"
        fi
      fi
    fi

    # Interpret sequences: ESC+Space toggles; arrows handled; standalone ESC exits
    if [[ -n "$seq_rest" && "${seq_rest:0:1}" == " " ]]; then
      # ESC + Space (Alt+Space) -> toggle
      if [[ ${sel[cursor]} -eq 1 ]]; then sel[cursor]=0; else sel[cursor]=1; fi
    elif [[ "$seq_rest" == "["* ]]; then
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
        *) ;;
      esac
    else
      # standalone ESC -> exit
      stty "$oldstty" < /dev/tty 2>/dev/null || true
      exec 3<&-
      printf "\nESC pressed (exit code 2)\n" > /dev/tty
      exit 2
    fi

  else
    # non-escape single key handling
    k1hex=$(hex_of_char "$key1" || true)
    case "$k1hex" in
      "0A"|"0D") # Enter
        done=1
        ;;
      "20"|"A0") # Space or NBSP
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

  # restore stty
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