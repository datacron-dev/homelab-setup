#!/bin/bash

# Developer-focused setup script (no sudo required)
# This script installs all components in user space

# Exit on any error
set -e

echo "[INFO] Starting developer environment setup for AI Workstation..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# === STEP 1: Install Miniforge (Conda/Mamba Replacement) ===
echo "[STEP 1/4] Installing Miniforge for isolated Python environments..."

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
echo "[STEP 2/4] Installing core Python packages (vLLM, Transformers, etc.)..."

# Ensure we're using the correct Python
PYTHON_BIN="$MINIFORGE_PATH/bin/python"
PIP_BIN="$MINIFORGE_PATH/bin/pip"

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

# === STEP 3: Install Node.js in User Space ===
echo "[STEP 3/4] Installing Node.js in user space..."

# Use Node Version Manager (NVM) for user-space Node.js installation
NVM_DIR="$HOME/.nvm"

if [ -d "$NVM_DIR" ]; then
    echo "[INFO] NVM already installed, updating..."
    cd "$NVM_DIR"
    git fetch origin
    git checkout $(git describe --abbrev=0 --tags)
    cd "$HOME"
else
    echo "[INFO] Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Source NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install latest LTS Node.js version
echo "[INFO] Installing latest LTS Node.js..."
nvm install --lts
nvm use --lts

NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
echo "[INFO] Node.js version: $NODE_VERSION"
echo "[INFO] npm version: $NPM_VERSION"

# === STEP 4: Clone and Setup Open WebUI ===
echo "[STEP 4/4] Cloning Open WebUI for local ChatGPT-style interface..."

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

# Create a startup script for Open WebUI
echo "[INFO] Creating Open WebUI startup script..."
cat > "$HOME/start_webui.sh" << 'EOF'
#!/bin/bash
cd $HOME/open-webui
$HOME/miniforge3/bin/python main.py
EOF

chmod +x "$HOME/start_webui.sh"

# Install additional development tools
echo "[INFO] Installing additional development tools..."

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
echo "   • Run 'ollama pull <model>' to download a model (e.g., llama3) - requires sysadmin to install Ollama."
echo "   • Start Open WebUI with './start_webui.sh'"
echo "   • Launch JupyterLab with 'jupyter lab'"
echo "   • Use Docker Compose with 'docker-compose'"
echo ""
echo "[IMPORTANT] For full functionality, please ask your system administrator to run 'setup_admin.sh'"
echo "[NOTE] You may need to restart your terminal or run 'source ~/.bashrc' to use the new tools."
