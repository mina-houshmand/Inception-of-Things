#!/bin/bash
# Installs K3s in server mode, then deploys the 3 apps and the Ingress.
set -e
SERVER_IP="$1"

IFACE=$(ip -o -4 addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2}')

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${SERVER_IP} \
  --flannel-iface=${IFACE} \
  --write-kubeconfig-mode=644" sh -

# Wait for the node to be ready
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 3; done

kubectl apply -f /vagrant/confs/

echo "alias k='kubectl'" >> /home/vagrant/.bashrc
