#!/bin/bash

# Exit on any error
set -e

echo "[INFO] Starting developer environment setup for AI Workstation..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to compare versions (returns 0 if versions are equal, 1 if v1 > v2, 2 if v1 < v2)
version_compare() {
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # Fill empty fields with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# === STEP 1: Install Miniforge (Conda/Mamba Replacement) ===
echo "[STEP 1/6] Installing Miniforge for isolated Python environments..."

MINIFORGE_PATH="$HOME/miniforge3"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"

# Check if Miniforge is already installed
if [ -d "$MINIFORGE_PATH" ]; then
    echo "[INFO] Miniforge already installed at $MINIFORGE_PATH"
    
    # Check if we can get version info
    if [ -f "$MINIFORGE_PATH/bin/conda" ]; then
        INSTALLED_VERSION=$("$MINIFORGE_PATH/bin/conda" --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
        echo "[INFO] Current Miniforge version: $INSTALLED_VERSION"
        
        # Attempt to update Miniforge
        echo "[INFO] Updating Miniforge..."
        if curl -fsSL "$MINIFORGE_URL" -o miniforge.sh; then
            bash miniforge.sh -b -u -p "$MINIFORGE_PATH"
            rm miniforge.sh
            echo "[INFO] Miniforge updated successfully"
        else
            echo "[WARN] Failed to download Miniforge installer, continuing with existing installation"
        fi
    else
        echo "[WARN] Conda binary not found, reinstalling Miniforge..."
        rm -rf "$MINIFORGE_PATH"
        curl -fsSL "$MINIFORGE_URL" -o miniforge.sh
        bash miniforge.sh -b -p "$MINIFORGE_PATH"
        rm miniforge.sh
    fi
else
    # Fresh installation
    echo "[INFO] Installing Miniforge..."
    curl -fsSL "$MINIFORGE_URL" -o miniforge.sh
    bash miniforge.sh -b -p "$MINIFORGE_PATH"
    rm miniforge.sh
fi

# Initialize conda for bash
"$MINIFORGE_PATH/bin/conda" init bash

# Source the conda environment to use it immediately
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

# === STEP 2: Install Core Python Packages ===
echo "[STEP 2/6] Installing core Python packages (vLLM, Transformers, etc.)..."

# Ensure we're using the correct Python
PYTHON_BIN="$MINIFORGE_PATH/bin/python"
PIP_BIN="$MINIFORGE_PATH/bin/pip"

# Install/update Python to version 3.10
CURRENT_PYTHON_VERSION=$($PYTHON_BIN --version 2>&1 | cut -d' ' -f2)
echo "[INFO] Current Python version: $CURRENT_PYTHON_VERSION"

# Install core packages with version checking
CORE_PACKAGES=("vllm" "transformers" "accelerate")

for package in "${CORE_PACKAGES[@]}"; do
    echo "[INFO] Checking $package..."
    if $PIP_BIN show "$package" > /dev/null 2>&1; then
        echo "[INFO] $package already installed, upgrading..."
        $PIP_BIN install --upgrade "$package"
    else
        echo "[INFO] Installing $package..."
        $PIP_BIN install "$package"
    fi
done

# === STEP 3: Install Node.js and npm ===
echo "[STEP 3/6] Installing Node.js and npm for web app development..."

# Check if Node.js is already installed
if command_exists node; then
    NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' || echo "unknown")
    echo "[INFO] Node.js version $NODE_VERSION already installed"
    
    # Check if it's version 20 or higher
    if [[ "$NODE_VERSION" =~ ^v([0-9]+) ]] && [[ ${BASH_REMATCH[1]} -ge 20 ]]; then
        echo "[INFO] Node.js version is sufficient, skipping installation"
    else
        echo "[INFO] Upgrading Node.js to version 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
else
    echo "[INFO] Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# === STEP 4: Clone and Setup Open WebUI ===
echo "[STEP 4/6] Cloning Open WebUI for local ChatGPT-style interface..."

OPEN_WEBUI_PATH="$HOME/open-webui"

# Check if Open WebUI is already cloned
if [ -d "$OPEN_WEBUI_PATH" ]; then
    echo "[INFO] Open WebUI already exists, updating repository..."
    cd "$OPEN_WEBUI_PATH"
    git pull origin main
else
    echo "[INFO] Cloning Open WebUI..."
    cd "$HOME"
    git clone https://github.com/open-webui/open-webui.git
    cd open-webui
fi

# Create/update .env file with default settings
echo "[INFO] Creating/updating .env file..."
cat > .env << EOF
OLLAMA_BASE_URL=http://localhost:11434
WEBUI_SECRET_KEY=your-super-secret-key-change-this
EOF

# Install/update Python dependencies
echo "[INFO] Installing/updating Python dependencies..."
$PIP_BIN install -r requirements.txt

# === STEP 5: Setup Auto-Start Scripts ===
echo "[STEP 5/6] Setting up auto-start for Ollama and Open WebUI..."

# Create a systemd service for Ollama (if not already installed as service)
echo "[INFO] Setting up Ollama systemd service..."
sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

# Enable the service if not already enabled
if systemctl is-enabled ollama >/dev/null 2>&1; then
    echo "[INFO] Ollama service already enabled"
else
    echo "[INFO] Enabling Ollama service..."
    sudo systemctl enable ollama
fi

# Create/update a startup script for Open WebUI
echo "[INFO] Creating/updating Open WebUI startup script..."
cat > "$HOME/start_webui.sh" << 'EOF'
#!/bin/bash
cd $HOME/open-webui
$HOME/miniforge3/bin/python main.py
EOF

chmod +x "$HOME/start_webui.sh"

# === STEP 6: Install Additional Dev Tools ===
echo "[STEP 6/6] Installing additional development tools..."

# Install JupyterLab
echo "[INSTALLING] JupyterLab..."
if $PIP_BIN show jupyterlab > /dev/null 2>&1; then
    echo "[INFO] JupyterLab already installed, upgrading..."
    $PIP_BIN install --upgrade jupyterlab
else
    echo "[INFO] Installing JupyterLab..."
    $PIP_BIN install jupyterlab
fi

# Install Docker Compose for user-level container management
echo "[INSTALLING] Docker Compose..."
if $PIP_BIN show docker-compose > /dev/null 2>&1; then
    echo "[INFO] Docker Compose already installed, upgrading..."
    $PIP_BIN install --upgrade docker-compose
else
    echo "[INFO] Installing Docker Compose..."
    $PIP_BIN install docker-compose
fi

# Final Instructions
echo ""
echo "[SUCCESS] Developer environment setup completed!"
echo "👉 You can now:"
echo "   • Use 'conda activate base' to access your Python environment."
echo "   • Run 'ollama pull <model>' to download a model (e.g., llama3)."
echo "   • Start Open WebUI with './start_webui.sh' or manually via Python."
echo "   • Launch JupyterLab with 'jupyter lab'"
echo "   • Use Docker Compose with 'docker-compose'"
echo ""
echo "[NOTE] Reboot recommended to ensure all services start correctly."
