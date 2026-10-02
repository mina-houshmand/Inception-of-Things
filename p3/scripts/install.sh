#!/bin/bash
# Installs everything Part 3 needs: Docker, kubectl, k3d.
# Run with: sudo bash install.sh
set -e

apt-get update
apt-get install -y curl ca-certificates git

# Docker
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
  # Let the normal user run docker without sudo (log out/in after this)
  usermod -aG docker "${SUDO_USER:-$USER}"
fi

# kubectl
if ! command -v kubectl >/dev/null; then
  VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
  install -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
fi

# k3d
if ! command -v k3d >/dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

echo "Done. docker, kubectl and k3d are installed."
