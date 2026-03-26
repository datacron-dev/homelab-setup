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
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_WHITE='\033[1;37m'
NC='\033[0m'

# --- Style A Menu Glyphs ---
# > [*] selected+focused   > [ ] unselected+focused
#   [*] selected            [ ] unselected
SEL_ON="[*]"
SEL_OFF="[ ]"
CURSOR=">"
NO_CURSOR=" "

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

# --- Pure-Bash Style A Checklist Engine ---
# Usage: bash_checklist <title> <prompt> <result_var> <default_on_keys_space_sep> item_key "Item Label" ...
# Returns 0 on Enter/confirm, 1 on ESC/back.
# Writes space-separated selected keys into result_var.
bash_checklist() {
    local title="$1"; shift
    local prompt="$1"; shift
    local result_var="$1"; shift
    local defaults="$1"; shift   # space-separated keys that start ON

    # Build items array from remaining args (pairs: key "label")
    local -a _keys _labels _sel
    local idx=0
    while [[ $# -ge 2 ]]; do
        _keys[idx]="$1"
        _labels[idx]="$2"
        # default ON if key is in defaults list
        if [[ " $defaults " == *" $1 "* ]]; then
            _sel[idx]=1
        else
            _sel[idx]=0
        fi
        ((idx++)) || true
        shift 2
    done
    local count=$idx
    local cursor=0
    local done_flag=0

    # Open /dev/tty for reading
    exec 4</dev/tty 2>/dev/null || { tty_print "ERROR: cannot open /dev/tty"; return 1; }
    local oldstty
    oldstty=$(stty -g </dev/tty 2>/dev/null || true)

    _menu_cleanup() {
        stty "$oldstty" </dev/tty 2>/dev/null || true
        exec 4<&- 2>/dev/null || true
        printf "%b" "$NC" >/dev/tty
    }

    _hex_of() { printf "%s" "$1" | od -An -t x1 | tr -s ' ' | sed 's/^ //' | tr '[:lower:]' '[:upper:]'; }

    while [[ $done_flag -eq 0 ]]; do
        # Draw screen
        printf "\033[H\033[2J" >/dev/tty
        printf "%b\n" "${GREEN}┌──────────────────────────────────────────────────────────────────────────┐${NC}" >/dev/tty
        printf "%b\n" "${GREEN}│${NC}  ${BRIGHT_WHITE}${title}${NC}" >/dev/tty
        printf "%b\n" "${GREEN}├──────────────────────────────────────────────────────────────────────────┤${NC}" >/dev/tty
        printf "%b\n" "${GREEN}│${NC}  ${GREEN}${prompt}${NC}" >/dev/tty
        printf "%b\n" "${GREEN}│${NC}  ${CYAN}↑/↓ move  Space toggle  Enter confirm  ESC back${NC}" >/dev/tty
        printf "%b\n" "${GREEN}└──────────────────────────────────────────────────────────────────────────┘${NC}" >/dev/tty
        printf "\n" >/dev/tty

        for ((i=0; i<count; i++)); do
            local cur_sym sel_sym label_color
            label_color="${GREEN}"
            if [[ $i -eq $cursor ]]; then
                cur_sym="${BRIGHT_WHITE}${CURSOR}${NC}"
                label_color="${BRIGHT_WHITE}"
            else
                cur_sym=" "
            fi
            if [[ ${_sel[i]} -eq 1 ]]; then
                sel_sym="${BRIGHT_GREEN}${SEL_ON}${NC}"
            else
                sel_sym="${GREEN}${SEL_OFF}${NC}"
            fi
            printf " %b %b %b%-20s%b  %b%s%b\n" \
                "$cur_sym" "$sel_sym" \
                "${BRIGHT_WHITE}" "${_keys[i]}" "${NC}" \
                "$label_color" "${_labels[i]}" "${NC}" >/dev/tty
        done

        printf "\n" >/dev/tty

        # Raw input
        stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
        local key1=""
        while true; do
            read -rsn1 -u 4 key1 2>/dev/null || true
            [[ -n "$key1" ]] && break
            sleep 0.02
        done

        if [[ $key1 == $'\x1b' ]]; then
            local seq_rest="" key2="" key3=""
            read -rsn1 -t 0.15 -u 4 key2 2>/dev/null || true
            if [[ -n "$key2" ]]; then
                seq_rest+="$key2"
                if [[ $key2 == "[" ]]; then
                    read -rsn1 -t 0.05 -u 4 key3 2>/dev/null || true
                    [[ -n "$key3" ]] && seq_rest+="$key3"
                fi
            fi
            if [[ "$seq_rest" == "[A"* ]]; then
                ((cursor--)) || true; [[ $cursor -lt 0 ]] && cursor=$((count-1))
            elif [[ "$seq_rest" == "[B"* ]]; then
                ((cursor++)) || true; [[ $cursor -ge $count ]] && cursor=0
            elif [[ -z "$seq_rest" || "$seq_rest" == $'\x1b' ]]; then
                # ESC -> back
                stty "$oldstty" </dev/tty 2>/dev/null || true
                exec 4<&- 2>/dev/null || true
                eval "$result_var=''"
                return 1
            fi
        else
            local k1hex
            k1hex=$(_hex_of "$key1" || true)
            case "$k1hex" in
                "0A"|"0D")  # Enter
                    done_flag=1 ;;
                "20"|"A0")  # Space
                    if [[ ${_sel[cursor]} -eq 1 ]]; then _sel[cursor]=0; else _sel[cursor]=1; fi ;;
                "78"|"58"|"73"|"53")  # x/X/s/S fallback toggle
                    if [[ ${_sel[cursor]} -eq 1 ]]; then _sel[cursor]=0; else _sel[cursor]=1; fi ;;
            esac
        fi

        stty "$oldstty" </dev/tty 2>/dev/null || true
    done

    stty "$oldstty" </dev/tty 2>/dev/null || true
    exec 4<&- 2>/dev/null || true

    # Build result string of selected keys
    local result=""
    for ((i=0; i<count; i++)); do
        [[ ${_sel[i]} -eq 1 ]] && result+="${_keys[i]} "
    done
    eval "$result_var='${result% }'"
    return 0
}

# Pure-Bash yes/no confirm prompt (Style A)
bash_confirm() {
    local title="$1"
    local msg="$2"
    exec 4</dev/tty 2>/dev/null || return 1
    local oldstty
    oldstty=$(stty -g </dev/tty 2>/dev/null || true)

    printf "\033[H\033[2J" >/dev/tty
    printf "%b\n" "${GREEN}┌──────────────────────────────────────────────────────────────────────────┐${NC}" >/dev/tty
    printf "%b\n" "${GREEN}│${NC}  ${BRIGHT_WHITE}${title}${NC}" >/dev/tty
    printf "%b\n" "${GREEN}└──────────────────────────────────────────────────────────────────────────┘${NC}" >/dev/tty
    printf "\n" >/dev/tty
    printf "%b\n" "  ${GREEN}${msg}${NC}" >/dev/tty
    printf "\n" >/dev/tty
    printf "%b" "  ${BRIGHT_WHITE}Proceed? [y/N]: ${NC}" >/dev/tty

    stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
    local ans=""
    while true; do
        read -rsn1 -u 4 ans 2>/dev/null || true
        [[ -n "$ans" ]] && break
        sleep 0.02
    done
    stty "$oldstty" </dev/tty 2>/dev/null || true
    exec 4<&- 2>/dev/null || true
    printf "\n" >/dev/tty
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# Pure-Bash summary box
bash_msgbox() {
    local title="$1"
    local msg="$2"
    printf "\033[H\033[2J" >/dev/tty
    printf "%b\n" "${GREEN}┌──────────────────────────────────────────────────────────────────────────┐${NC}" >/dev/tty
    printf "%b\n" "${GREEN}│${NC}  ${BRIGHT_WHITE}${title}${NC}" >/dev/tty
    printf "%b\n" "${GREEN}└──────────────────────────────────────────────────────────────────────────┘${NC}" >/dev/tty
    printf "\n" >/dev/tty
    printf "%b\n" "${GREEN}${msg}${NC}" >/dev/tty
    printf "\n" >/dev/tty
    printf "%b" "  ${CYAN}Press any key to exit...${NC}" >/dev/tty
    exec 4</dev/tty 2>/dev/null || true
    local oldstty
    oldstty=$(stty -g </dev/tty 2>/dev/null || true)
    stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
    local k=""
    while true; do
        read -rsn1 -u 4 k 2>/dev/null || true
        [[ -n "$k" ]] && break
        sleep 0.02
    done
    stty "$oldstty" </dev/tty 2>/dev/null || true
    exec 4<&- 2>/dev/null || true
    printf "\n" >/dev/tty
}

# --- UI Menus (stream-safe: use /dev/tty) ---

show_main_menu() {
    local CHOICES=""
    while true; do
        if bash_checklist \
            "System Onboard - Software" \
            "Select programs to install. Space to toggle, Enter to confirm, ESC to exit." \
            CHOICES \
            "docker vscode tailscale ollama" \
            docker    "Docker Engine ($ARCH)" \
            vscode    "Visual Studio Code" \
            tailscale "Tailscale VPN" \
            brave     "Brave Browser" \
            ollama    "Ollama (Local LLM Runner)" \
            lmstudio  "LM Studio" \
            openclaw  "OpenClaw Quickstart"
        then
            # Save selections to state
            tmp=$(jq --argjson apps "$(printf '%s\n' $CHOICES | jq -R . | jq -s .)" '.selected.apps = $apps' "$STATE_FILE")
            echo "$tmp" > "$STATE_FILE"
            break
        else
            tty_print "Exiting onboarding."
            exit 0
        fi
    done
}

show_model_menu() {
    local MODELS=""
    if bash_checklist \
        "System Onboard - Models" \
        "Select Ollama models to download. Space to toggle, Enter to confirm, ESC to go back." \
        MODELS \
        "llama3.1:8b" \
        "llama3.1:8b"  "Llama 3.1 8B  (~4.7 GB)" \
        "llama3.1:70b" "Llama 3.1 70B (~40 GB)"
    then
        tmp=$(jq --argjson models "$(printf '%s\n' $MODELS | jq -R . | jq -s .)" '.selected.models = $models' "$STATE_FILE")
        echo "$tmp" > "$STATE_FILE"
        return 0
    else
        return 1
    fi
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
            if bash_confirm "Ollama Required" "Ollama is required to pull models. Install Ollama now?"; then
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

if ! bash_confirm "Ready to Install" "The script will now install your selections. Progress logged to: $LOG_FILE"; then
    tty_print "Installation cancelled."
    exit 0
fi

run_installs

# Final Summary
SUMMARY=$(jq -r '.completed | to_entries[] | "  - \(.key): \(.value)"' "$STATE_FILE" 2>/dev/null || echo "  No items processed.")
bash_msgbox "Onboarding Complete" "The following items were processed:\n\n${SUMMARY}\n\n  Log saved to: ${LOG_FILE}"