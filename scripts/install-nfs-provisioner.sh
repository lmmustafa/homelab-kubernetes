#!/usr/bin/env bash

set -euo pipefail

CHART_REPO="nfs-subdir-external-provisioner"
CHART="${CHART_REPO}/nfs-subdir-external-provisioner"
CHART_VERSION="4.0.18"
RELEASE="nfs-provisioner"
NAMESPACE="nfs-provisioner"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES="${ROOT_DIR}/manifests/storage/nfs-subdir-external-provisioner/values-homelab.yaml"

command -v kubectl >/dev/null || {
  echo "ERRO: kubectl não encontrado."
  exit 1
}

command -v helm >/dev/null || {
  echo "ERRO: Helm não encontrado."
  exit 1
}

test -f "$VALUES" || {
  echo "ERRO: arquivo de configuração não encontrado: $VALUES"
  exit 1
}

echo "===== INSTALAÇÃO DO PROVISIONADOR NFS ====="
echo "Contexto Kubernetes: $(kubectl config current-context)"
echo "Servidor NFS:       10.10.1.240"
echo "Exportação:          /srv/nfs/k8s"
echo "StorageClass:        nfs-server-k8s"
echo "Namespace:           nfs-provisioner"
echo "Chart:               $CHART_VERSION"
echo

read -r -p "Digite INSTALAR para confirmar a instalação/atualização: " CONFIRM

if [[ "$CONFIRM" != "INSTALAR" ]]; then
  echo "Operação cancelada. Nenhuma alteração foi aplicada."
  exit 0
fi

helm repo add "$CHART_REPO" \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
  --force-update

helm repo update

helm upgrade --install "$RELEASE" "$CHART" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES" \
  --wait \
  --timeout 5m

echo
echo "===== PODS DO PROVISIONADOR ====="
kubectl -n "$NAMESPACE" get pods -o wide

echo
echo "===== STORAGECLASS ====="
kubectl get storageclass nfs-server-k8s

echo
echo "Instalação concluída."
