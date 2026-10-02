#!/bin/bash
# Installs K3s in server (controller) mode.
set -e
SERVER_IP="$1"

# Find the network interface that has our private IP (eth1, enp0s8, ...)
IFACE=$(ip -o -4 addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2}')

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${SERVER_IP} \
  --flannel-iface=${IFACE} \
  --write-kubeconfig-mode=644" sh -

# Share the join token with the worker through the synced /vagrant folder
until [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done
cp /var/lib/rancher/k3s/server/node-token /vagrant/confs/node-token

# Shortcut: "k" = kubectl
echo "alias k='kubectl'" >> /home/vagrant/.bashrc
