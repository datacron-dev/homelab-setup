#!/bin/bash

# System administrator setup script (requires sudo privileges)
# This script handles all system-level installations and configurations

# Exit on any error
set -e

echo "[INFO] Starting full system-level setup for AI Workstation..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# === STEP 1: System Updates ===
echo "[STEP 1/11] Updating system packages..."
sudo apt update && sudo apt full-upgrade -y

# === STEP 2: Install Core Dev Tools ===
echo "[STEP 2/11] Installing dev essentials: git, htop, jq, wget, curl..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y git htop jq wget curl tree build-essential cmake ninja-build pkg-config libgl1

# === STEP 3: Install and Enable Docker Service ===
echo "[STEP 3/11] Installing and enabling Docker service..."
if command_exists docker; then
    echo "[INFO] Docker already installed"
else
    echo "[INFO] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
fi

echo "[INFO] Ensuring Docker service is active and enabled..."
sudo systemctl enable docker --now

# === STEP 4: Install Docker Compose ===
echo "[STEP 4/11] Installing Docker Compose..."
if command_exists docker-compose; then
    echo "[INFO] Docker Compose already installed"
    docker-compose --version
else
    echo "[INFO] Installing Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    docker-compose --version
fi

# === STEP 5: Interactive Add Users to Docker Group ===
echo "[STEP 5/11] Configure Docker access for users..."

if [ -t 0 ]; then
    read -p "Do you want to add any users to the 'docker' group? (y/N): " add_user_choice
else
    read -p "Do you want to add any users to the 'docker' group? (y/N): " add_user_choice < /dev/tty || add_user_choice="N"
fi

if [[ "$add_user_choice" =~ ^[Yy]$ ]]; then
    while true; do
        read -p "Enter username to add to 'docker' group: " username < /dev/tty

        if id "$username" &>/dev/null; then
            echo "✔ Adding '$username' to the 'docker' group..."
            sudo usermod -aG docker "$username"
        else
            echo "⚠ User '$username' does not exist. Please check the username and try again."
            continue
        fi

        read -p "Add another user to 'docker' group? (y/N): " add_another < /dev/tty || add_another="N"
        if [[ ! "$add_another" =~ ^[Yy]$ ]]; then
            break
        fi
    done
else
    echo "⏭ Skipping Docker group assignment."
fi

# === STEP 6: Install NoMachine Server for Remote GUI Access ===
echo "[STEP 6/11] Installing NoMachine server..."
NM_DOWNLOAD_URL="https://download.nomachine.com/download/8.10/Linux/nomachine_8.10.11_1_amd64.deb"
echo "Downloading NoMachine from ${NM_DOWNLOAD_URL}"
wget --max-redirect=10 --trust-server-names -O nomachine.deb "${NM_DOWNLOAD_URL}"
if dpkg-deb --info nomachine.deb >/dev/null 2>&1; then
    sudo dpkg -i nomachine.deb || sudo apt-get install -f -y
    if systemctl list-unit-files | grep -q '^nxserver'; then
        sudo systemctl enable nxserver || true
    else
        echo "NoMachine installed but nxserver unit not found. Skipping enable."
    fi
else
    echo "Downloaded file is not a valid .deb - skipping NoMachine installation."
fi
rm -f nomachine.deb

# === STEP 7: Install Additional AI Workstation Tools ===
echo "[STEP 7/11] Installing monitoring/storage tools (nvtop, gdu, ipmitool, git-lfs, nfs-common, iperf3)..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y nvtop ipmitool nfs-common iperf3 git-lfs
sudo systemctl stop iperf3 || true
sudo systemctl disable iperf3 || true

git lfs install

if command_exists gdu; then
    echo "[INFO] GDU already installed"
else
    echo "[INFO] Installing GDU..."
    curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
    sudo mv gdu_linux_amd64 /usr/local/bin/gdu
    sudo chmod +x /usr/local/bin/gdu
fi

# === STEP 8: Install Fabric Manager for Multi-GPU Support ===
echo "[STEP 8/11] Installing NVIDIA Fabric Manager..."
if command_exists nvidia-smi; then
    sudo apt-get update
    sudo apt-get -y -o Dpkg::Options::="--force-overwrite" install nvidia-fabricmanager-580 || {
        echo "⚠️ Fabric manager install hit a conflict; attempting to fix broken dependencies..."
        sudo apt-get install -f -y
    }
    sudo systemctl enable --now nvidia-fabricmanager || true
else
    echo "[WARN] NVIDIA drivers not detected. Skipping Fabric Manager installation."
fi

# === STEP 9: Optimize System for VS Code Remote ===
echo "[STEP 9/11] Increasing inotify watches for VS Code..."
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# === STEP 10: Install Ollama (Local LLM Backend) ===
echo "[STEP 10/11] Installing Ollama as system-wide AI backend..."
if command_exists ollama; then
    echo "[INFO] Ollama already installed"
else
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Create a dedicated system user for Ollama service if not exists
OLLAMA_USER="ollama"
if id "$OLLAMA_USER" &>/dev/null; then
    echo "[INFO] Ollama user exists"
else
    echo "[INFO] Creating Ollama system user..."
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$OLLAMA_USER"
fi

# Create a systemd service for Ollama running as ollama user
echo "[INFO] Setting up Ollama systemd service..."
sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=$OLLAMA_USER
Group=$OLLAMA_USER

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

if systemctl is-enabled ollama >/dev/null 2>&1; then
    echo "[INFO] Ollama service already enabled"
else
    echo "[INFO] Enabling Ollama service..."
    sudo systemctl enable ollama
fi

# === STEP 11: Install VS Code GUI Locally ===
echo "[STEP 11/11] Install Visual Studio Code (GUI) locally?"

read -p "Install VS Code GUI on this machine? (y/N): " install_vscode_gui
if [[ "$install_vscode_gui" =~ ^[Yy]$ ]]; then
    if command_exists code; then
        echo "[INFO] VS Code already installed"
    else
        echo "✔ Installing VS Code (amd64)..."
        wget -O vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
        sudo dpkg -i vscode.deb || sudo apt-get install -f -y
        rm vscode.deb
        echo "✔ VS Code installed. You can now launch it from Applications or run 'code' in terminal."
    fi
else
    echo "⏭ Skipping local VS Code installation."
fi

# === Cleanup ===
echo "[CLEANUP] Removing orphaned packages..."
sudo apt autoremove -y && sudo apt autoclean

echo ""
echo "[SUCCESS] Full sys-admin setup completed!"
echo "👉 You can now:"
echo "   • Connect via SSH normally."
echo "   • Use VS Code with Remote SSH extension."
echo "   • Use NoMachine client to connect (default port: 4000)"
echo "   • Run Ollama commands system-wide"
echo ""
echo "[NOTE] Reboot recommended to finalize all services (especially FabricManager)."
echo "      Also, run 'sudo tailscale up' manually to authenticate Tailscale VPN if needed."
