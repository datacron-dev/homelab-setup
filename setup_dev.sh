#!/bin/bash

# Exit on any error
set -e

echo "[INFO] Starting developer environment setup for AI Workstation..."

# === STEP 1: Install Miniforge (Conda/Mamba Replacement) ===
echo "[STEP 1/6] Installing Miniforge for isolated Python environments..."
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
curl -fsSL $MINIFORGE_URL -o miniforge.sh
bash miniforge.sh -b -p $HOME/miniforge3
rm miniforge.sh

# Initialize conda for bash
$HOME/miniforge3/bin/conda init bash

# Source the conda environment to use it immediately
source $HOME/.bashrc

# === STEP 2: Install Core Python Packages ===
echo "[STEP 2/6] Installing core Python packages (vLLM, Transformers, etc.)..."
$HOME/miniforge3/bin/conda install -y python=3.10
$HOME/miniforge3/bin/pip install vllm transformers accelerate

# === STEP 3: Install Node.js and npm ===
echo "[STEP 3/6] Installing Node.js and npm for web app development..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# === STEP 4: Clone and Setup Open WebUI ===
echo "[STEP 4/6] Cloning Open WebUI for local ChatGPT-style interface..."
cd $HOME
git clone https://github.com/open-webui/open-webui.git
cd open-webui

# Create a .env file with default settings
cat > .env << EOF
OLLAMA_BASE_URL=http://localhost:11434
WEBUI_SECRET_KEY=your-super-secret-key-change-this
EOF

# Install Python dependencies
$HOME/miniforge3/bin/pip install -r requirements.txt

# === STEP 5: Setup Auto-Start Scripts ===
echo "[STEP 5/6] Setting up auto-start for Ollama and Open WebUI..."

# Create a systemd service for Ollama (if not already installed as service)
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
sudo systemctl enable ollama

# Create a startup script for Open WebUI
cat > $HOME/start_webui.sh << 'EOF'
#!/bin/bash
cd $HOME/open-webui
$HOME/miniforge3/bin/python main.py
EOF

chmod +x $HOME/start_webui.sh

# === STEP 6: Install Additional Dev Tools ===
echo "[STEP 6/6] Installing additional development tools..."

# Install JupyterLab
echo "[INSTALLING] JupyterLab..."
$HOME/miniforge3/bin/pip install jupyterlab

# Install Docker Compose for user-level container management
echo "[INSTALLING] Docker Compose..."
$HOME/miniforge3/bin/pip install docker-compose

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
