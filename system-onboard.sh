#!/usr/bin/env bash
#
# system-onboard.sh - AI Workstation Onboarding (Ubuntu 24.04 LTS)
# Target: x86_64 / arm64
#
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

# Intro disclaimer header
echo -e "${RED}${BOLD}  🤖 SYSTEM ONBOARD 🤖  ${NC}"
echo -e "\n${RED}System onboarding${NC}"
echo -e "${CYAN}Security ──────────────────────────────────────────────────────────────────${NC}"
echo -e "│                                                                          │"
echo -e "│  ${BOLD}Security warning - please read.${NC}                                         │"
echo -e "│                                                                          │"
echo -e "│  This script will perform a streamlined setup of your AI workstation.    │"
echo -e "│  It will install and configure the following assets:                     │"
echo -e "│  - ${CYAN}Docker, VS Code, Tailscale, Brave${NC}                                     │"
echo -e "│  - ${CYAN}Ollama, LM Studio, OpenClaw${NC}                                           │"
echo -e "│  - ${CYAN}Llama 3.1 Models (8B & 70B)${NC}                                           │"
echo -e "│                                                                          │"
echo -e "│  By continuing, you acknowledge that these tools can read files and      │"
echo -e "│  execute actions on your system. Ensure you are on a secure network.     │"
echo -e "│                                                                          │"
echo -e "│  Target Architecture: ${BOLD}$ARCH${NC}                                               │"
echo -e "│                                                                          │"
echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
echo ""


# --- Configuration & Paths ---
STATE_DIR="/var/lib/system-onboard"
STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="/var/log/system-onboard.log"
OS_CODENAME=$(lsb_release -sc)

# --- Initialization ---
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

# Ensure jq is installed for state management
if ! command -v jq >/dev/null 2>&1; then
    apt-get update && apt-get install -y jq >> "$LOG_FILE" 2>&1
fi

# --- Architecture Detection ---
ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" ]]; then
    echo "Error: Unsupported architecture ($ARCH). Only x86_64 and arm64 are supported."
    exit 1
fi

# --- State Helpers ---
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
    fi
}

is_done() { jq -e --arg k "$1" '.completed[$k] == "success"' "$STATE_FILE" >/dev/null 2>&1; }
mark_done() { tmp=$(jq --arg k "$1" '.completed[$k] = "success"' "$STATE_FILE"); echo "$tmp" > "$STATE_FILE"; }

# --- Install Functions ---

install_docker() {
    if is_done "docker"; then return 0; fi
    echo "Installing Docker ($ARCH)..." | tee -a "$LOG_FILE"
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y ca-certificates curl gnupg >> "$LOG_FILE" 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $OS_CODENAME stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
    mark_done "docker"
}

install_vscode() {
    if is_done "vscode"; then return 0; fi
    echo "Installing VS Code ($ARCH)..." | tee -a "$LOG_FILE"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y code >> "$LOG_FILE" 2>&1
    mark_done "vscode"
}

install_tailscale() {
    if is_done "tailscale"; then return 0; fi
    echo "Installing Tailscale..." | tee -a "$LOG_FILE"
    curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG_FILE" 2>&1
    mark_done "tailscale"
}

install_ollama() {
    if is_done "ollama"; then return 0; fi
    echo "Installing Ollama..." | tee -a "$LOG_FILE"
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    mark_done "ollama"
}

install_openclaw() {
    if is_done "openclaw"; then return 0; fi
    echo "Installing OpenClaw..." | tee -a "$LOG_FILE"
    curl -fsSL https://openclaw.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    mark_done "openclaw"
}

install_lmstudio() {
    if is_done "lmstudio"; then return 0; fi
    echo "Installing LM Studio..." | tee -a "$LOG_FILE"
    curl -fsSL https://lmstudio.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    mark_done "lmstudio"
}

pull_model() {
    local model=$1
    if is_done "model_$model"; then return 0; fi
    echo "Pulling model: $model (This may take a while)..." | tee -a "$LOG_FILE"
    ollama pull "$model" >> "$LOG_FILE" 2>&1
    mark_done "model_$model"
}

# --- UI Menus ---

show_main_menu() {
    CHOICES=$(whiptail --title "System Onboard - Software" --checklist \
    "Select programs to install (Space to select, Enter to confirm)" 20 78 10 \
    "docker" "Docker Engine ($ARCH)" ON \
    "vscode" "Visual Studio Code" ON \
    "tailscale" "Tailscale VPN" ON \
    "brave" "Brave Browser" OFF \
    "ollama" "Ollama (Local LLM Runner)" ON \
    "lmstudio" "LM Studio" OFF \
    "openclaw" "OpenClaw Quickstart" OFF 3>&1 1>&2 2>&3) || exit 0

    # Save selections to state
    tmp=$(jq --arg c "$CHOICES" '.selected.apps = ($c | split(" ") | map(gsub("\""; "")))' "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
}

show_model_menu() {
    MODELS=$(whiptail --title "System Onboard - Models" --checklist \
    "Select models to download via Ollama" 20 78 10 \
    "llama3.1:8b" "Llama 3.1 8B (~4.7 GB)" ON \
    "llama3.1:70b" "Llama 3.1 70B (~40 GB)" OFF 3>&1 1>&2 2>&3) || return 0

    tmp=$(jq --arg m "$MODELS" '.selected.models = ($m | split(" ") | map(gsub("\""; "")))' "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
}

# --- Execution Loop ---

run_installs() {
    # Apps
    APPS=$(jq -r '.selected.apps[]' "$STATE_FILE" 2>/dev/null || true)
    for app in $APPS; do
        case $app in
            docker) install_docker ;;
            vscode) install_vscode ;;
            tailscale) install_tailscale ;;
            ollama) install_ollama ;;
            openclaw) install_openclaw ;;
            lmstudio) install_lmstudio ;;
        esac
    done

    # Models (Requires Ollama)
    MODELS=$(jq -r '.selected.models[]' "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$MODELS" ]]; then
        if ! command -v ollama >/dev/null 2>&1; then install_ollama; fi
        for model in $MODELS; do
            pull_model "$model"
        done
    fi
}

# --- Main Entry ---
init_state
show_main_menu
show_model_menu

whiptail --title "Ready" --yesno "The script will now begin installing your selections. View progress in $LOG_FILE. Proceed?" 10 60 || exit 0

run_installs

# Final Summary
SUMMARY=$(jq -r '.completed | to_entries[] | "- \(.key): \(.value)"' "$STATE_FILE")
whiptail --title "Onboarding Complete" --msgbox "The following items were processed:\n\n$SUMMARY\n\nLog saved to $LOG_FILE" 20 70