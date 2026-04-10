# 🧠 AI Workstation Setup Scripts

Automated setup scripts for initializing your **AI Workstation** (e.g., Gigabyte AI TOP ATOM) from scratch. This project focuses on **zero-cloud sovereignty**, secure local AI development, and optimized multi-GPU orchestration.

---

## 📦 What's Included

### 👨‍💻 `setup_admin.sh` — System-Level Initialization

Designed for the **admin user** (`sys-admin`), this script handles:

- **System Update & Core Tools**: `git`, `htop`, `wget`, `curl`, `build-essential`, `cmake`, etc.
- **Docker & Docker Compose**: Enables container-based AI development.
- **GPU Support**: Installs **NVIDIA Fabric Manager** for optimized multi-GPU communication.
- **Remote Access**:
  - **NoMachine**: For high-performance remote desktop.
  - **Tailscale**: Secure mesh VPN (installed, requires manual activation).
- **Monitoring & Utilities**:
  - `nvtop`: Real-time GPU monitoring.
  - `gdu`: Fast disk usage analyzer.
  - `iperf3`, `ipmitool`, `git-lfs`.
- **Developer Experience**:
  - Increases `inotify` limit for **VS Code Remote SSH**.
  - Installs **Ollama** as a system-wide LLM backend.
  - Optional local **VS Code GUI** install for physical access.

---

### 👨‍🔬 `setup_dev.sh` — Developer Environment Setup

For the **development user** (`ai-dev`), this includes:

- **Miniforge** (lightweight conda/mamba replacement).
- **vLLM** for high-speed local inference.
- **Open WebUI** (local ChatGPT-style interface).
- **Node.js / npm** for web app development.
- Auto-start scripts for local AI agents.

---

## ⚙️ Quickstart

### Run Admin Setup

```bash
curl -fsSL https://raw.githubusercontent.com/datacron-dev/homelab-setup/main/setup_admin.sh | bash
```

The script will walk you through:
- Adding users to Docker group.
- Choosing optional tools like VS Code.

---

## 📌 Post-Install Steps

After the script completes:
```bash
sudo reboot
sudo tailscale up    # Join your secure Tailnet
ollama serve &       # Start Ollama (optional)
```

---

## 🧪 Verify GPU Access

Test Docker with NVIDIA:

```bash
sudo docker run --rm --gpus all nvcr.io/nvidia/cuda:12.6.0-runtime-ubuntu22.04 nvidia-smi
```

You should see your GPUs detected.

---

## 🛡️ Security & Privacy

All tools are **offline-first**:
- No data leaves your machine unless explicitly pushed.
- VPN secured via Tailscale.
- Runs entirely on-prem.

---

## 🤝 Contributing

Want to improve this setup? Fork it and submit a PR!

---

## 📄 License

MIT License
