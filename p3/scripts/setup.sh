#!/bin/bash
# Creates the k3d cluster, the namespaces, installs Argo CD and the app.
# Run from the p3 folder: bash scripts/setup.sh
set -e

k3d cluster create iot

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD to be ready..."
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s

kubectl apply -f confs/application.yaml

echo ""
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "Open the UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then go to:   https://localhost:8080  (user: admin)"
