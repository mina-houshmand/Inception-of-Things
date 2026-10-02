#!/bin/bash
# Installs K3s in agent mode and joins the server.
set -e
SERVER_IP="$1"
WORKER_IP="$2"

IFACE=$(ip -o -4 addr show | awk -v ip="$WORKER_IP" '$4 ~ "^"ip"/" {print $2}')

# Wait until the server has written its token
until [ -f /vagrant/confs/node-token ]; do
  echo "Waiting for the server token..."
  sleep 5
done

curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="$(cat /vagrant/confs/node-token)" \
  INSTALL_K3S_EXEC="agent --node-ip=${WORKER_IP} --flannel-iface=${IFACE}" sh -
