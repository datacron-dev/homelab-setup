#!/usr/bin/env bash
#
# system-onboard.sh - AI Workstation Onboarding (Ubuntu 24.04 LTS)
# Stream-friendly: designed to be run as:
#   curl -fsSL https://raw.githubusercontent.com/datacron-dev/homelab-setup/main/system-onboard.sh | bash
#
set -euo pipefail

# --- Helpers ---
# Print to the user's terminal (works when script is piped)
tty_print() { printf "%b\n" "$*" > /dev/tty; }

# Detect whether running as root; set SUDO_CMD to use when needed
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO_CMD=""
    STATE_DIR="/var/lib/system-onboard"
    LOG_FILE="/var/log/system-onboard.log"
else
    SUDO_CMD="sudo"
    STATE_DIR="${HOME}/.system-onboard"
    LOG_FILE="${HOME}/.system-onboard.log"
fi

# --- Architecture Detection (early) ---
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "unknown")
if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" ]]; then
    tty_print "Warning: Detected architecture: ${ARCH}. Supported: amd64, arm64."
fi

# --- Colors (for custom menus and tty prints) ---
GREEN='\033[0;32m'
WHITE='\033[0;37m'
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Whiptail / Newt Theme (kept for compatibility if whiptail used elsewhere) ---
export NEWT_COLORS='
  root=,black
  window=,black
  border=green,black
  shadow=,black
  button=green,black
  actbutton=white,black
  compactbutton=green,black
  title=green,black
  label=green,black
  textbox=green,black
  acttextbox=white,black
  entry=green,black
  disentry=darkgreen,black
  checkbox=green,black
  actcheckbox=white,black
  listbox=green,black
  actlistbox=white,black
'

# --- Print header to the terminal (not stdout) ---
tty_print "${BOLD}${WHITE}  🤖 SYSTEM ONBOARD 🤖  ${NC}"
tty_print ""
tty_print "${BOLD}System onboarding${NC}"
tty_print "${CYAN}Security ──────────────────────────────────────────────────────────────────${NC}"
tty_print "│                                                                          │"
tty_print "│  ${BOLD}Security warning - please read.${NC}                                         │"
tty_print "│                                                                          │"
tty_print "│  This script will perform a streamlined setup of your AI workstation.    │"
tty_print "│  It will install and configure the following assets:                     │"
tty_print "│  - ${CYAN}Docker, VS Code, Tailscale, Brave${NC}                                     │"
tty_print "│  - ${CYAN}Ollama, LM Studio, OpenClaw${NC}                                           │"
tty_print "│  - ${CYAN}Llama 3.1 Models (8B & 70B)${NC}                                           │"
tty_print "│                                                                          │"
tty_print "│  By continuing, you acknowledge that these tools can read files and      │"
tty_print "│  execute actions on your system. Ensure you are on a secure network.     │"
tty_print "│                                                                          │"
tty_print "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
tty_print ""

# --- Configuration & Paths ---
STATE_FILE="$STATE_DIR/state.json"
OS_CODENAME=$(lsb_release -sc 2>/dev/null || echo "unknown")

# --- Initialization ---
mkdir -p "$STATE_DIR"
touch "$LOG_FILE" 2>/dev/null || true

# --- Ensure helper tools exist (jq) ---
ensure_pkg() {
  local cmd="$1"; local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -z "$SUDO_CMD" ]]; then
      tty_print "Installing missing dependency: $pkg ..."
      apt-get update -y >> "$LOG_FILE" 2>&1
      apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
    else
      if command -v sudo >/dev/null 2>&1; then
        if whiptail --title "Dependency required" --yesno "This script requires '$pkg' (command: $cmd). Install it now using sudo?" 10 60 </dev/tty; then
          tty_print "Installing $pkg via sudo..."
          $SUDO_CMD apt-get update -y >> "$LOG_FILE" 2>&1
          $SUDO_CMD apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
        else
          tty_print "Dependency '$pkg' is required. Please install it and re-run the script."
          exit 1
        fi
      else
        tty_print "Missing '$pkg' and sudo not available. Please install '$pkg' and re-run."
        exit 1
      fi
    fi
  fi
}

ensure_pkg jq jq

# --- State Helpers ---
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
    else
        # ensure valid json
        if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
            echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
        fi
    fi
}

is_done() { jq -e --arg k "$1" '.completed[$k] == "success"' "$STATE_FILE" >/dev/null 2>&1; }
mark_done() { tmp=$(jq --arg k "$1" '.completed[$k] = "success"' "$STATE_FILE"); echo "$tmp" > "$STATE_FILE"; }

# --- Install helper to pick apt/sudo/tee usage ---
write_file_root() {
  local path="$1"; shift
  local content="$*"
  if [[ -z "$SUDO_CMD" ]]; then
    printf "%s" "$content" > "$path"
  else
    printf "%s" "$content" | $SUDO_CMD tee "$path" >/dev/null
  fi
}

# --- Install Functions (unchanged) ---
install_docker() {
    if is_done "docker"; then return 0; fi
    tty_print "Installing Docker ($ARCH)... (this requires root privileges)"
    if [[ -z "$SUDO_CMD" ]]; then
      apt-get update -y >> "$LOG_FILE" 2>&1
      apt-get install -y ca-certificates curl gnupg >> "$LOG_FILE" 2>&1
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      write_file_root /etc/apt/sources.list.d/docker.list "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $OS_CODENAME stable"
      apt-get update -y >> "$LOG_FILE" 2>&1
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
    else
      $SUDO_CMD apt-get update -y >> "$LOG_FILE" 2>&1
      $SUDO_CMD apt-get install -y ca-certificates curl gnupg >> "$LOG_FILE" 2>&1
      $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes | $SUDO_CMD tee /etc/apt/keyrings/docker.gpg >/dev/null
      write_file_root /etc/apt/sources.list.d/docker.list "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $OS_CODENAME stable"
      $SUDO_CMD apt-get update -y >> "$LOG_FILE" 2>&1
      $SUDO_CMD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
    fi
    mark_done "docker"
}

install_vscode() {
    if is_done "vscode"; then return 0; fi
    tty_print "Installing VS Code ($ARCH)... (this requires root privileges)"
    if [[ -z "$SUDO_CMD" ]]; then
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
      write_file_root /etc/apt/sources.list.d/vscode.list "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
      apt-get update -y >> "$LOG_FILE" 2>&1
      apt-get install -y code >> "$LOG_FILE" 2>&1
    else
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes | $SUDO_CMD tee /etc/apt/keyrings/microsoft.gpg >/dev/null
      write_file_root /etc/apt/sources.list.d/vscode.list "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
      $SUDO_CMD apt-get update -y >> "$LOG_FILE" 2>&1
      $SUDO_CMD apt-get install -y code >> "$LOG_FILE" 2>&1
    fi
    mark_done "vscode"
}

install_tailscale() {
    if is_done "tailscale"; then return 0; fi
    tty_print "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG_FILE" 2>&1
    mark_done "tailscale"
}

install_ollama() {
    if is_done "ollama"; then return 0; fi
    tty_print "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    mark_done "ollama"
}

install_openclaw() {
    if is_done "openclaw"; then return 0; fi
    tty_print "Installing OpenClaw..."
    curl -fsSL https://openclaw.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    mark_done "openclaw"
}

install_lmstudio() {
    if is_done "lmstudio"; then return 0; fi
    tty_print "Installing LM Studio..."
    curl -fsSL https://lmstudio.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    mark_done "lmstudio"
}

pull_model() {
    local model=$1
    if is_done "model_$model"; then return 0; fi
    tty_print "Pulling model: $model (This may take a while)..."
    ollama pull "$model" >> "$LOG_FILE" 2>&1
    mark_done "model_$model"
}

# --- Custom Unicode circle checklist UI (stream-safe) ---

# Generic UI builder reused by both menus
# Parameters:
#  $1 -> Title label (string)
#  $2 -> newline-separated items in "key|Label" format (string)
#  $3 -> state_key ("apps" or "models") used to store to .selected.$state_key
# Returns:
#   0 on confirm (Enter)
#   1 on left-arrow/back
#   2 on ESC (exit)
show_unicode_checklist() {
    local title="$1"
    local items_blob="$2"
    local state_key="$3"

    # build items array
    IFS=$'\n' read -r -d '' -a items < <(printf "%s\0" "$items_blob")

    # initialize selection array
    declare -a sel
    local i=0
    for pair in "${items[@]}"; do
      sel[$i]=0
      ((i++))
    done
    local count=${#items[@]}

    # load saved selections if present
    if [[ -f "$STATE_FILE" ]]; then
      local saved
      saved=$(jq -r --arg key "$state_key" '.selected[$key][]?' "$STATE_FILE" 2>/dev/null || true)
      if [[ -n "$saved" ]]; then
        while IFS= read -r s; do
          i=0
          for pair in "${items[@]}"; do
            key="${pair%%|*}"
            if [[ "$key" == "$s" ]]; then
              sel[$i]=1
            fi
            ((i++))
          done
        done <<< "$saved"
      fi
    fi

    # prepare /dev/tty input
    exec 3</dev/tty

    local oldstty
    oldstty=$(stty -g)
    trap 'stty "$oldstty"; exec 3<&-; printf "%b" "$NC" > /dev/tty' RETURN INT TERM

    local cursor=0
    local done=0
    while [[ $done -eq 0 ]]; do
      # draw UI
      printf "\033[H\033[2J" > /dev/tty
      printf "%b\n" "${GREEN}┌───────────────────────────────────────────────────────────────┐${NC}" > /dev/tty
      printf "%b\n" "${GREEN}│${NC}  ${title} ${GREEN}                             │${NC}" > /dev/tty
      printf "%b\n" "${GREEN}└───────────────────────────────────────────────────────────────┘${NC}" > /dev/tty
      printf "\n" > /dev/tty
      printf "%b\n" "${GREEN}Use ↑/↓ to move, Space to toggle, Enter to confirm, ← to go back, ESC to exit${NC}" > /dev/tty
      printf "\n" > /dev/tty

      i=0
      for pair in "${items[@]}"; do
        key="${pair%%|*}"
        label="${pair#*|}"

        if [[ $i -eq $cursor ]]; then
          # focused: white filled circle + white label
          printf "%b " "${WHITE}●${NC}" > /dev/tty
          printf "%b\n" "${WHITE}${label}${NC}" > /dev/tty
        else
          if [[ ${sel[$i]} -eq 1 ]]; then
            printf "%b " "${GREEN}●${NC}" > /dev/tty
            printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
          else
            printf "%b " "${GREEN}○${NC}" > /dev/tty
            printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
          fi
        fi
        ((i++))
      done

      # read key input
      stty -echo -icanon time 0 min 0
      local key1 key2 key3 seq
      key1=""
      while true; do
        read -rsn1 -u 3 key1 2>/dev/null || true
        if [[ -n "$key1" ]]; then break; fi
        sleep 0.02
      done

      if [[ $key1 == $'\x1b' ]]; then
        # possible arrow sequence
        read -rsn1 -t 0.01 -u 3 key2 2>/dev/null || true
        read -rsn1 -t 0.01 -u 3 key3 2>/dev/null || true
        seq="$key2$key3"
        case "$seq" in
          "[A") # up
            ((cursor--)); if [[ $cursor -lt 0 ]]; then cursor=$((count-1)); fi
            ;;
          "[B") # down
            ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi
            ;;
          "[D") # left -> back
            stty "$oldstty"
            exec 3<&-
            return 1
            ;;
          "[C") # right -> next (treat as down)
            ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi
            ;;
          *) # standalone ESC -> exit
            stty "$oldstty"
            exec 3<&-
            return 2
            ;;
        esac
      elif [[ $key1 == $'\x0a' || $key1 == $'\x0d' ]]; then
        # Enter -> confirm
        done=1
      elif [[ $key1 == " " ]]; then
        # toggle
        if [[ ${sel[$cursor]} -eq 1 ]]; then
          sel[$cursor]=0
        else
          sel[$cursor]=1
        fi
      fi
    done

    # restore terminal and close fd
    stty "$oldstty"
    exec 3<&-

    # build selected keys
    local sel_keys=()
    i=0
    for pair in "${items[@]}"; do
      key="${pair%%|*}"
      if [[ ${sel[$i]} -eq 1 ]]; then
        sel_keys+=("$key")
      fi
      ((i++))
    done

    # write state back
    if [[ ${#sel_keys[@]} -gt 0 ]]; then
      tmp=$(jq --argjson arr "$(printf '%s\n' "${sel_keys[@]}" | jq -R . | jq -s .)" ".selected[\"$state_key\"] = \$arr" "$STATE_FILE")
      echo "$tmp" > "$STATE_FILE"
    else
      tmp=$(jq ".selected[\"$state_key\"] = []" "$STATE_FILE")
      echo "$tmp" > "$STATE_FILE"
    fi

    return 0
}

# --- Menus using the generic UI ---

show_main_menu() {
  local items=$'docker|Docker Engine ('"$ARCH"')\nvscode|Visual Studio Code\ntailscale|Tailscale VPN\nbrave|Brave Browser\nollama|Ollama (Local LLM Runner)\nlmstudio|LM Studio\nopenclaw|OpenClaw Quickstart'
  show_unicode_checklist "System Onboard - Software" "$items" "apps"
  return $?
}

show_model_menu() {
  local items=$'llama3.1:8b|Llama 3.1 8B (~4.7 GB)\nllama3.1:70b|Llama 3.1 70B (~40 GB)'
  show_unicode_checklist "System Onboard - Models" "$items" "models"
  return $?
}

# --- Execution Loop ---

run_installs() {
    # Apps
    APPS=$(jq -r '.selected.apps[]?' "$STATE_FILE" 2>/dev/null || true)
    for app in $APPS; do
        case $app in
            docker) install_docker ;;
            vscode) install_vscode ;;
            tailscale) install_tailscale ;;
            ollama) install_ollama ;;
            openclaw) install_openclaw ;;
            lmstudio) install_lmstudio ;;
            brave) tty_print "Brave install not yet implemented; skipping." ;;
            *) tty_print "Unknown app: $app" ;;
        esac
    done

    # Models (Requires Ollama)
    MODELS=$(jq -r '.selected.models[]?' "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$MODELS" ]]; then
        if ! command -v ollama >/dev/null 2>&1; then
            if whiptail --title "Ollama required" --yesno "Ollama is required to pull models. Install Ollama now?" 10 60 </dev/tty; then
                install_ollama
            else
                tty_print "Skipping model downloads because Ollama is not installed."
                return
            fi
        fi
        for model in $MODELS; do
            pull_model "$model"
        done
    fi
}

# --- Main Entry ---

init_state

# top-level loop to allow returning from model menu
while true; do
  # show main menu
  if ! show_main_menu; then
    rc=$?
    if [[ $rc -eq 2 ]]; then
      tty_print "Exiting onboarding."
      exit 0
    else
      # back (1) at top-level => exit
      tty_print "Exiting onboarding."
      exit 0
    fi
  fi

  # show model menu
  if ! show_model_menu; then
    rc=$?
    if [[ $rc -eq 1 ]]; then
      # user pressed left to go back to main menu: loop again
      continue
    elif [[ $rc -eq 2 ]]; then
      tty_print "Exiting onboarding."
      exit 0
    fi
  fi

  # confirm and proceed
  if ! whiptail --title "Ready" --yesno "The script will now begin installing your selections. View progress in $LOG_FILE. Proceed?" 10 60 </dev/tty; then
      tty_print "Installation cancelled."
      exit 0
  fi

  run_installs

  break
done

# Final Summary
SUMMARY=$(jq -r '.completed | to_entries[] | "- \(.key): \(.value)"' "$STATE_FILE" 2>/dev/null || echo "No items processed.")
whiptail --title "Onboarding Complete" --msgbox "The following items were processed:\n\n$SUMMARY\n\nLog saved to $LOG_FILE" 20 70 </dev/tty