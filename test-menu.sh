#!/bin/bash

# Initial Setup
INITIAL_STATE=$(jq -r '.completed, .selected' "$STATE_FILE")

if [[ -z "$INITIAL_STATE" ]]; then
    echo '{"completed":{}, "selected":{}}' > "$STATE_FILE"
fi

# Main Menu
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
            printf "%s" "$tmp" > "$STATE_FILE"
            break
        elif [[ $RET -eq 1 || $RET -eq 255 ]]; then
            # Cancel or ESC pressed - exit onboarding
            printf "Exiting onboarding.\n" >&2
            exit 0
        fi
    done
}

# Model Menu (Requires Ollama)
show_model_menu() {
    while true; do
        MODELS=$(
          whiptail --title "System Onboard - Models" --checklist \
            "Select models to download via Ollama\n\nPress ESC or Cancel to go back." 20 78 10 \
            "llama3.1:8b" "Llama 3.1 8B (~4.7 GB)" ON \
            "llama3.1:70b" "Llama 3.1 70B (~40 GB)" OFF \
            3>&1 1>&2 2>&3 </dev/tty
        )
        RET=$?
        if [[ $RET -eq 0 ]]; then
            local cleaned
            cleaned=$(printf "%s" "$MODELS" | sed 's/"//g' | awk '{$1=$1};1')
            tmp=$(jq --argjson models "$(printf '%s\n' $cleaned | jq -R . | jq -s .)" '.selected.models = $models' "$STATE_FILE")
            printf "%s" "$tmp" > "$STATE_FILE"
            break
        elif [[ $RET -eq 1 || $RET -eq 255 ]]; then
            # Cancel or ESC pressed - go back to main menu
            return 1
        fi
    done
}

# Execution Loop
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

# Install Functions

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    else
        tty_print "Docker is already installed."
    fi
}

install_vscode() {
    if ! command -v code >/dev/null 2>&1; then
        install_vscode
    else
        tty_print "VS Code is already installed."
    fi
}

install_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        install_tailscale
    else
        tty_print "Tailscale is already installed."
    fi
}

install_ollama() {
    if ! command -v ollama >/dev/null 2>&1; then
        curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    else
        tty_print "Ollama is already installed."
    fi
}

install_openclaw() {
    if ! command -v openclaw >/dev/null 2>&1; then
        curl -fsSL https://openclaw.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    else
        tty_print "OpenClaw is already installed."
    fi
}

install_lmstudio() {
    if ! command -v lmstudio >/dev/null 2>&1; then
        curl -fsSL https://lmstudio.ai/install.sh | bash >> "$LOG_FILE" 2>&1
    else
        tty_print "LM Studio is already installed."
    fi
}

pull_model() {
    local model=$1
    if ! command -v ollama >/dev/null 2>&1; then
        install_ollama
    fi
    ollama pull "$model" >> "$LOG_FILE" 2>&1
}

# Main Execution

show_main_menu

if ! whiptail --title "Ready" --yesno "The script will now begin installing your selections. View progress in $LOG_FILE. Proceed?" 10 60 </dev/tty; then
    printf "Installation cancelled.\n" >&2
    exit 0
fi

run_installs

# Final Summary
SUMMARY=$(jq -r '.completed | to_entries[] | "- \(.key): \(.value)"' "$STATE_FILE" 2>/dev/null || echo "No items processed.")
whiptail --title "Onboarding Complete" --msgbox "The following items were processed:\n\n$SUMMARY\n\nLog saved to $LOG_FILE" 20 70 </dev/tty