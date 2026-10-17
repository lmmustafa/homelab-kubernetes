#!/usr/bin/env bash

set -euo pipefail

CHART_REPO="nfs-subdir-external-provisioner"
CHART="${CHART_REPO}/nfs-subdir-external-provisioner"
CHART_VERSION="4.0.18"
RELEASE="nfs-provisioner"
NAMESPACE="nfs-provisioner"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES="${ROOT_DIR}/manifests/storage/nfs-subdir-external-provisioner/values-homelab.yaml"
RENDERED="/tmp/nfs-provisioner-rendered.yaml"

echo "===== VERIFICAR FERRAMENTAS ====="
command -v kubectl
command -v helm

echo
echo "===== CONTEXTO KUBERNETES ====="
kubectl config current-context

echo
echo "===== STATUS DOS NODES ====="
kubectl get nodes

echo
echo "===== VALIDAR ARQUIVO DE CONFIGURAÇÃO ====="
test -f "$VALUES"
echo "OK - $VALUES"

echo
echo "===== ATUALIZAR REPOSITÓRIO HELM ====="
helm repo add "$CHART_REPO" \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
  --force-update

helm repo update

echo
echo "===== RENDERIZAR MANIFESTS ====="
helm template "$RELEASE" "$CHART" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --values "$VALUES" > "$RENDERED"

echo "OK - arquivo gerado: $RENDERED"

echo
echo "===== VALIDAR NA API SEM INSTALAR ====="
kubectl apply --dry-run=server -f "$RENDERED"

echo
echo "===== VALIDAR REFERÊNCIAS IMPORTANTES ====="
grep -nE \
  'kind: StorageClass|nfs-server-k8s|homelab.local/nfs-server-k8s|10.10.1.240|/srv/nfs/k8s|k8s-worker-01|k8s-worker-02|reclaimPolicy: Retain' \
  "$RENDERED"

echo
echo "VALIDAÇÃO CONCLUÍDA."
echo "Nenhum recurso Kubernetes foi instalado por este script."
