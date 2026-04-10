#!/bin/bash

# Exit on any error
set -e

echo "[INFO] Starting full system-level setup for AI Workstation..."

# === STEP 1: System Updates ===
echo "[STEP 1/10] Updating system packages..."
sudo apt update && sudo apt full-upgrade -y

# === STEP 2: Install Core Dev Tools ===
echo "[STEP 2/10] Installing dev essentials: git, htop, jq, wget, curl..."
sudo apt install -y git htop jq wget curl tree build-essential cmake ninja-build pkg-config libgl1

# === STEP 3: Enable Docker Service ===
echo "[STEP 3/10] Ensuring Docker service is active and enabled..."
sudo systemctl enable docker --now

# === STEP 4: Install Docker Compose ===
echo "[STEP 4/10] Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version

# === STEP 5: Interactive Add Users to Docker Group ===
echo "[STEP 5/10] Configure Docker access for users..."

read -p "Do you want to add any users to the 'docker' group? (y/N): " add_user_choice

if [[ "$add_user_choice" =~ ^[Yy]$ ]]; then
    while true; do
        read -p "Enter username to add to 'docker' group: " username

        # Check if user exists
        if id "$username" &>/dev/null; then
            echo "✔ Adding '$username' to the 'docker' group..."
            sudo usermod -aG docker "$username"
        else
            echo "⚠ User '$username' does not exist. Please check the username and try again."
            continue
        fi

        read -p "Add another user to 'docker' group? (y/N): " add_another
        if [[ ! "$add_another" =~ ^[Yy]$ ]]; then
            break
        fi
    done
else
    echo "⏭ Skipping Docker group assignment."
fi

# === STEP 6: Install NoMachine Server for Remote GUI Access ===
echo "[STEP 6/10] Installing NoMachine server..."

NM_DOWNLOAD_URL="https://download.nomachine.com/download/8.10/Linux/nomachine_8.10.11_1_amd64.deb"

wget --max-redirect=10 --trust-server-names -O nomachine.deb "$NM_DOWNLOAD_URL"

# Check if the downloaded file is a valid Debian package
if dpkg-deb --info nomachine.deb > /dev/null 2>&1; then
    sudo dpkg -i nomachine.deb || sudo apt-get install -f -y
    sudo systemctl enable nxserver
else
    echo "❌ Failed to download a valid NoMachine Debian package. Please check the URL or download manually."
    rm nomachine.deb
fi

# === STEP 7: Install Additional AI Workstation Tools ===
echo "[STEP 7/10] Installing monitoring/storage tools (nvtop, gdu, ipmitool, git-lfs, nfs-common, iperf3)..."
sudo apt install -y nvtop ipmitool nfs-common iperf3 git-lfs
git lfs install

# Fast disk usage analyzer
curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
sudo mv gdu_linux_amd64 /usr/local/bin/gdu
sudo chmod +x /usr/local/bin/gdu

# === STEP 8: Install Fabric Manager for Multi-GPU Support ===
echo "[STEP 8/10] Installing NVIDIA Fabric Manager..."
sudo apt install -y nvidia-fabricmanager-580
sudo systemctl enable --now nvidia-fabricmanager

# === STEP 9: Optimize System for VS Code Remote ===
echo "[STEP 9/10] Increasing inotify watches for VS Code..."
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# === STEP 10: Install Ollama (Local LLM Backend) ===
echo "[STEP 10/10] Installing Ollama as system-wide AI backend..."
curl -fsSL https://ollama.com/install.sh | sh

# === STEP 11: Install VS Code GUI Locally ===
echo "[OPTIONAL] Install Visual Studio Code (GUI) locally?"

read -p "Install VS Code GUI on this machine? (y/N): " install_vscode_gui
if [[ "$install_vscode_gui" =~ ^[Yy]$ ]]; then
    echo "✔ Installing VS Code (amd64)..."
    wget -O vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    sudo dpkg -i vscode.deb || sudo apt-get install -f -y
    rm vscode.deb
    echo "✔ VS Code installed. You can now launch it from Applications or run 'code' in terminal."
else
    echo "⏭ Skipping local VS Code installation."
fi

# === Cleanup ===
echo "[CLEANUP] Removing orphaned packages..."
sudo apt autoremove -y && sudo apt autoclean

# Final Output
echo ""
echo "[SUCCESS] Full sys-admin setup completed!"
echo "👉 You can now:"
echo "   • Connect via SSH normally."
echo "   • Use VS Code with Remote SSH extension."
echo "   • Use NoMachine client to connect (default port: 4000)"
echo ""
echo "[NOTE] Reboot recommended to finalize all services (especially FabricManager)."
echo "      Also, run 'sudo tailscale up' manually to authenticate Tailscale VPN."
