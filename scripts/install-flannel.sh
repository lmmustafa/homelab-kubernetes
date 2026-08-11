#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação e Validação do Flannel
# Homelab Kubernetes
# ============================================================
#
# Kubernetes:
#   v1.36.3
#
# Pod CIDR:
#   10.244.0.0/16
#
# CNI:
#   Flannel
#
# Executar no k8s-master-01
#
# ============================================================

FLANNEL_NAMESPACE="kube-flannel"
FLANNEL_MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
EXPECTED_POD_CIDR="10.244.0.0/16"

echo
echo "============================================================"
echo " Instalação e Validação do Flannel"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute o script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./install-flannel.sh"
    exit 1
fi

echo "[1/7] Verificando kubectl..."

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERRO: kubectl não encontrado."
    exit 1
fi

echo "kubectl: OK"
echo

# ============================================================
# Kubeconfig
# ============================================================

if [ -z "${KUBECONFIG:-}" ]; then

    if [ -f /etc/kubernetes/admin.conf ]; then
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo "KUBECONFIG configurado:"
        echo "  $KUBECONFIG"
    else
        echo "ERRO: /etc/kubernetes/admin.conf não encontrado."
        exit 1
    fi

else

    echo "KUBECONFIG:"
    echo "  $KUBECONFIG"

fi

echo

# ============================================================
# Verificar acesso ao cluster
# ============================================================

echo "[2/7] Validando acesso ao Kubernetes..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERRO: não foi possível acessar o Kubernetes."
    exit 1
fi

echo "Kubernetes API: OK"
echo

# ============================================================
# Verificar Nodes
# ============================================================

echo "[3/7] Validando Nodes..."

kubectl get nodes -o wide

echo

READY_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null |
    awk '$2 == "Ready" {count++} END {print count+0}')

if [ "$READY_NODES" -lt 1 ]; then
    echo "ERRO: nenhum Node está Ready."
    exit 1
fi

echo "Nodes Ready: $READY_NODES"
echo

# ============================================================
# Validar Pod CIDR
# ============================================================

echo "[4/7] Validando Pod CIDR..."

echo "CIDR esperado:"
echo "  $EXPECTED_POD_CIDR"
echo

kubectl get nodes \
    -o custom-columns='NODE:.metadata.name,POD-CIDR:.spec.podCIDR'

echo

POD_CIDRS=$(kubectl get nodes \
    -o jsonpath='{range .items[*]}{.spec.podCIDR}{"\n"}{end}')

if ! echo "$POD_CIDRS" | grep -q "10.244."; then
    echo "AVISO: não foi encontrado Pod CIDR 10.244.x.x."
    echo
fi

# ============================================================
# Verificar instalação do Flannel
# ============================================================

echo "[5/7] Verificando Flannel..."

if kubectl get namespace "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then

    echo "Namespace $FLANNEL_NAMESPACE: encontrado"

else

    echo "Flannel ainda não está instalado."
    echo
    echo "Aplicando manifesto:"
    echo "$FLANNEL_MANIFEST"
    echo

    kubectl apply -f "$FLANNEL_MANIFEST"

fi

echo

# ============================================================
# Aguardar Flannel
# ============================================================

echo "[6/7] Aguardando Flannel..."

if kubectl get daemonset kube-flannel-ds \
    -n "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then

    kubectl rollout status \
        daemonset/kube-flannel-ds \
        -n "$FLANNEL_NAMESPACE" \
        --timeout=180s

else

    echo "ERRO: DaemonSet kube-flannel-ds não encontrado."
    exit 1

fi

echo

# ============================================================
# Validação final
# ============================================================

echo "[7/7] Validação final..."

echo
echo "============================================================"
echo " FLANNEL"
echo "============================================================"
echo

echo "Pods:"
kubectl get pods \
    -n "$FLANNEL_NAMESPACE" \
    -o wide

echo

echo "DaemonSet:"
kubectl get daemonset \
    -n "$FLANNEL_NAMESPACE"

echo

echo "Nodes:"
kubectl get nodes -o wide

echo

FLANNEL_RUNNING=$(kubectl get pods \
    -n "$FLANNEL_NAMESPACE" \
    --no-headers 2>/dev/null |
    awk '$3 == "Running" {count++} END {print count+0}')

FLANNEL_DESIRED=$(kubectl get daemonset kube-flannel-ds \
    -n "$FLANNEL_NAMESPACE" \
    -o jsonpath='{.status.desiredNumberScheduled}')

echo "Flannel Running : $FLANNEL_RUNNING"
echo "Flannel Desired : $FLANNEL_DESIRED"
echo

if [ "$FLANNEL_RUNNING" -eq "$FLANNEL_DESIRED" ] && [ "$FLANNEL_DESIRED" -gt 0 ]; then

    echo "============================================================"
    echo " FLANNEL CONFIGURADO COM SUCESSO"
    echo "============================================================"
    echo
    echo "Namespace : $FLANNEL_NAMESPACE"
    echo "Pod CIDR  : $EXPECTED_POD_CIDR"
    echo "Modo      : CNI"
    echo
    echo "Próxima etapa:"
    echo "  Validar comunicação entre Pods."
    echo

else

    echo "============================================================"
    echo " ERRO: FLANNEL NÃO ESTÁ COMPLETAMENTE PRONTO"
    echo "============================================================"
    echo

    kubectl get pods \
        -n "$FLANNEL_NAMESPACE" \
        -o wide

    exit 1

fi