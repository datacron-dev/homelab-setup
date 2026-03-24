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
    # allow continuing for testing, but you may want to exit here:
    # exit 1
fi

# --- Colors ---
RED='\033[0;31m'
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Whiptail / Newt Theme ---
# Inactive: green text on black background
# Active (focused): white text on black background for high contrast
export NEWT_COLORS='
  root=,black
  window=,black
  border=green,black
  shadow=,black

  # Buttons: green text (inactive); white text when active
  button=green,black
  actbutton=white,black
  compactbutton=green,black

  # Title and labels: green on black
  title=green,black
  label=green,black

  # Text areas / entries / lists / checkboxes: green when idle, white when active
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
tty_print "${RED}${BOLD}  🤖 SYSTEM ONBOARD 🤖  ${NC}"
tty_print ""
tty_print "${RED}System onboarding${NC}"
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

# --- Ensure helper tools exist (jq, whiptail) ---
ensure_pkg() {
  local cmd="$1"; local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -z "$SUDO_CMD" ]]; then
      # running as root: install directly
      tty_print "Installing missing dependency: $pkg ..."
      apt-get update -y >> "$LOG_FILE" 2>&1
      apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
    else
      # not root: ask user if we can install using sudo
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
ensure_pkg whiptail whiptail

# --- State Helpers ---
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
    fi
}

is_done() { jq -e --arg k "$1" '.completed[$k] == "success"' "$STATE_FILE" >/dev/null 2>&1; }
mark_done() { tmp=$(jq --arg k "$1" '.completed[$k] = "success"' "$STATE_FILE"); echo "$tmp" > "$STATE_FILE"; }

# --- Install helper to pick apt/sudo/tee usage ---
write_file_root() {
  # usage: write_file_root "/etc/apt/sources.list.d/foo.list" "content..."
  local path="$1"; shift
  local content="$*"
  if [[ -z "$SUDO_CMD" ]]; then
    printf "%s" "$content" > "$path"
  else
    printf "%s" "$content" | $SUDO_CMD tee "$path" >/dev/null
  fi
}

# --- Install Functions ---

install_docker() {
    if is_done "docker"; then return 0; fi
    tty_print "Installing Docker ($ARCH)... (this requires root privileges)"
    # install prerequisites
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
    # tailscale installer runs as normal user but uses sudo inside if needed
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

# --- UI Menus (stream-safe: use /dev/tty) ---

show_main_menu() {
    while true; do
        CHOICES=$(
          whiptail --title "System Onboard - Software" --checklist \
            "Select programs to install (Space to select, Enter to confirm)\n\nPress ESC or Cancel to exit onboarding." 20 78 10 \
            "docker" "Docker Engine ($ARCH)" ON \
            "vscode" "Visual Studio Code" ON \
            "tailscale" "Tailscale VPN" ON \
            "brave" "Brave Browser" OFF \
            "ollama" "Ollama (Local LLM Runner)" ON \
            "lmstudio" "LM Studio" OFF \
            "openclaw" "OpenClaw Quickstart" OFF \
            3>&1 1>&2 2>&3 </dev/tty
        )
        RET=$?
        if [[ $RET -eq 0 ]]; then
            # Save selections to state
            local cleaned
            cleaned=$(printf "%s" "$CHOICES" | sed 's/"//g' | awk '{$1=$1};1')
            tmp=$(jq --argjson apps "$(printf '%s\n' $cleaned | jq -R . | jq -s .)" '.selected.apps = $apps' "$STATE_FILE")
            echo "$tmp" > "$STATE_FILE"
            break
        elif [[ $RET -eq 1 || $RET -eq 255 ]]; then
            # Cancel or ESC pressed - exit onboarding
            tty_print "Exiting onboarding."
            exit 0
        fi
    done
}

show_main_menu() {
    # items in "id|Label" format
    local items=(
      "docker|Docker Engine ($ARCH)"
      "vscode|Visual Studio Code"
      "tailscale|Tailscale VPN"
      "brave|Brave Browser"
      "ollama|Ollama (Local LLM Runner)"
      "lmstudio|LM Studio"
      "openclaw|OpenClaw Quickstart"
    )

    # colors (fallback if terminal does not support)
    local GREEN='\033[0;32m'
    local WHITE='\033[0;37m'
    local NC='\033[0m'

    # load previous selections if present
    declare -A sel
    local i=0 key name
    for pair in "${items[@]}"; do
      name="${pair%%|*}"
      sel[$i]=0
      ((i++))
    done
    # load saved selections from STATE_FILE if exists
    if [[ -f "$STATE_FILE" ]]; then
      local saved
      saved=$(jq -r '.selected.apps[]?' "$STATE_FILE" 2>/dev/null || true)
      if [[ -n "$saved" ]]; then
        while read -r s; do
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

    # terminal io fd for reading
    exec 3</dev/tty

    # save terminal state and ensure cleanup
    local oldstty
    oldstty=$(stty -g)
    trap 'stty "$oldstty"; exec 3<&-; printf "%b" "$NC" > /dev/tty' RETURN INT TERM

    # keyboard handling vars
    local cursor=0
    local count=${#items[@]}
    local done=0

    while [[ $done -eq 0 ]]; do
      # clear and draw
      printf "\033[H\033[2J" > /dev/tty
      printf "%b\n" "${GREEN}┌───────────────────────────────────────────────────────────────┐${NC}" > /dev/tty
      printf "%b\n" "${GREEN}│${NC}  System Onboard - Software${GREEN}                             │${NC}" > /dev/tty
      printf "%b\n" "${GREEN}└───────────────────────────────────────────────────────────────┘${NC}" > /dev/tty
      printf "\n" > /dev/tty
      printf "%b\n" "Use ↑/↓ to move, Space to toggle, Enter to confirm, ← to go back, ESC to exit" > /dev/tty
      printf "\n" > /dev/tty

      i=0
      for pair in "${items[@]}"; do
        key="${pair%%|*}"
        label="${pair#*|}"

        if [[ $i -eq $cursor ]]; then
          # focused row: white filled circle regardless of selection (per request)
          printf "%b " "${WHITE}●${NC}" > /dev/tty
          printf "%b\n" "${WHITE}${label}${NC}" > /dev/tty
        else
          if [[ ${sel[$i]} -eq 1 ]]; then
            # selected but not focused: green filled
            printf "%b " "${GREEN}●${NC}" > /dev/tty
            printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
          else
            # not selected and not focused: green empty circle
            printf "%b " "${GREEN}○${NC}" > /dev/tty
            printf "%b\n" "${GREEN}${label}${NC}" > /dev/tty
          fi
        fi
        ((i++))
      done

      # read key (handle arrow escape sequences)
      stty -echo -icanon time 0 min 0
      # wait for keypress
      local key1 key2 key3 seq
      key1=""
      while true; do
        read -rsn1 -u 3 key1 2>/dev/null || true
        if [[ -n "$key1" ]]; then break; fi
        sleep 0.02
      done

      # If ESC (could be arrow or standalone)
      if [[ $key1 == $'\x1b' ]]; then
        # try to read two more bytes for arrow sequences
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
          "[D") # left (back)
            # restore stty and close fd then return 1 to indicate back
            stty "$oldstty"
            exec 3<&-
            return 1
            ;;
          "[C") # right (skip) -> treat same as down
            ((cursor++)); if [[ $cursor -ge $count ]]; then cursor=0; fi
            ;;
          *) # standalone ESC -> exit onboarding
            stty "$oldstty"
            exec 3<&-
            return 2
            ;;
        esac
      elif [[ $key1 == $'\x0a' || $key1 == $'\x0d' ]]; then
        # Enter -> confirm
        done=1
      elif [[ $key1 == " " ]]; then
        # space -> toggle selection at cursor
        if [[ ${sel[$cursor]} -eq 1 ]]; then
          sel[$cursor]=0
        else
          sel[$cursor]=1
        fi
      fi
    done

    # restore terminal state and close descriptor
    stty "$oldstty"
    exec 3<&-

    # build JSON array of selected keys and write to STATE_FILE
    local sel_keys=()
    i=0
    for pair in "${items[@]}"; do
      key="${pair%%|*}"
      if [[ ${sel[$i]} -eq 1 ]]; then
        sel_keys+=("$key")
      fi
      ((i++))
    done

    # Write into state.json .selected.apps
    if [[ ${#sel_keys[@]} -gt 0 ]]; then
      tmp=$(jq --argjson apps "$(printf '%s\n' "${sel_keys[@]}" | jq -R . | jq -s .)" '.selected.apps = $apps' "$STATE_FILE")
      echo "$tmp" > "$STATE_FILE"
    else
      tmp=$(jq '.selected.apps = []' "$STATE_FILE")
      echo "$tmp" > "$STATE_FILE"
    fi

    return 0
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

if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
    echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
fi

show_main_menu

if ! show_model_menu; then
    # User pressed ESC or Cancel in model menu, go back to main menu or exit
    tty_print "Returning to main menu..."
    show_main_menu
fi

if ! whiptail --title "Ready" --yesno "The script will now begin installing your selections. View progress in $LOG_FILE. Proceed?" 10 60 </dev/tty; then
    tty_print "Installation cancelled."
    exit 0
fi

run_installs

# Final Summary
SUMMARY=$(jq -r '.completed | to_entries[] | "- \(.key): \(.value)"' "$STATE_FILE" 2>/dev/null || echo "No items processed.")
whiptail --title "Onboarding Complete" --msgbox "The following items were processed:\n\n$SUMMARY\n\nLog saved to $LOG_FILE" 20 70 </dev/tty