#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação e Validação do Flannel
# Homelab Kubernetes
# ============================================================
#
# Kubernetes:
#   v1.36.x
#
# Pod CIDR:
#   10.244.0.0/16
#
# CNI:
#   Flannel
#
# Executar SOMENTE no Control Plane
#
# ============================================================

FLANNEL_NAMESPACE="kube-flannel"
FLANNEL_MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
EXPECTED_POD_CIDR="10.244.0.0/16"

echo
echo "============================================================"
echo " INSTALAÇÃO DO FLANNEL"
echo "============================================================"
echo

# ============================================================
# 1. Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute o script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./install-flannel.sh"
    exit 1
fi

echo "[1/10] Verificando ambiente..."

# ============================================================
# 2. Verificar kubectl
# ============================================================

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERRO: kubectl não encontrado."
    exit 1
fi

echo "kubectl : OK"

# ============================================================
# 3. Configurar KUBECONFIG
# ============================================================

if [ -z "${KUBECONFIG:-}" ]; then

    if [ -f /etc/kubernetes/admin.conf ]; then

        export KUBECONFIG=/etc/kubernetes/admin.conf

        echo "KUBECONFIG:"
        echo "  $KUBECONFIG"

    else

        echo
        echo "ERRO: /etc/kubernetes/admin.conf não encontrado."
        echo
        echo "Execute este script no Control Plane após:"
        echo
        echo "  kubeadm init"
        echo

        exit 1

    fi

else

    echo "KUBECONFIG:"
    echo "  $KUBECONFIG"

fi

echo

# ============================================================
# 4. Verificar API Server
# ============================================================

echo "[2/10] Verificando Kubernetes API..."

if ! kubectl cluster-info >/dev/null 2>&1; then

    echo
    echo "ERRO: Kubernetes API não está disponível."
    echo

    kubectl cluster-info || true

    exit 1

fi

echo "Kubernetes API : OK"
echo

# ============================================================
# 5. Mostrar estado atual dos Nodes
# ============================================================

echo "[3/10] Estado atual dos Nodes..."

kubectl get nodes -o wide

echo

echo "IMPORTANTE:"
echo "Node NotReady neste momento é esperado."
echo "O Flannel será instalado antes de exigir Node Ready."
echo

# ============================================================
# 6. Validar Pod CIDR
# ============================================================

echo "[4/10] Validando Pod CIDR..."

echo
echo "Pod CIDR esperado:"
echo "  $EXPECTED_POD_CIDR"
echo

kubectl get nodes \
    -o custom-columns='NODE:.metadata.name,POD-CIDR:.spec.podCIDR'

echo

POD_CIDRS=$(kubectl get nodes \
    -o jsonpath='{range .items[*]}{.spec.podCIDR}{"\n"}{end}')

if ! echo "$POD_CIDRS" | grep -q "10.244."; then

    echo
    echo "AVISO:"
    echo "Nenhum Pod CIDR 10.244.x.x foi encontrado."
    echo
    echo "Verifique se o cluster foi inicializado com:"
    echo
    echo "  --pod-network-cidr=10.244.0.0/16"
    echo

else

    echo "Pod CIDR : OK"

fi

echo

# ============================================================
# 7. Instalar / atualizar Flannel
# ============================================================

echo "[5/10] Instalando / atualizando Flannel..."

echo
echo "Manifesto:"
echo "$FLANNEL_MANIFEST"
echo

kubectl apply -f "$FLANNEL_MANIFEST"

echo
echo "Manifesto do Flannel aplicado com sucesso."
echo

# ============================================================
# 8. Verificar DaemonSet
# ============================================================

echo "[6/10] Verificando DaemonSet do Flannel..."

for i in {1..30}; do

    if kubectl get daemonset kube-flannel-ds \
        -n "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then

        echo "DaemonSet encontrado."
        break

    fi

    echo "Aguardando DaemonSet..."
    sleep 5

done

if ! kubectl get daemonset kube-flannel-ds \
    -n "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then

    echo
    echo "ERRO: DaemonSet kube-flannel-ds não foi encontrado."
    echo

    kubectl get all \
        -n "$FLANNEL_NAMESPACE" || true

    exit 1

fi

echo

# ============================================================
# 9. Aguardar Flannel
# ============================================================

echo "[7/10] Aguardando Flannel ficar Ready..."

kubectl rollout status \
    daemonset/kube-flannel-ds \
    -n "$FLANNEL_NAMESPACE" \
    --timeout=180s

echo
echo "Flannel : Ready"
echo

# ============================================================
# 10. Aguardar Nodes
# ============================================================

echo "[8/10] Aguardando Nodes ficarem Ready..."

for i in {1..36}; do

    NOT_READY=$(kubectl get nodes \
        --no-headers 2>/dev/null |
        awk '$2 != "Ready" {count++} END {print count+0}')

    TOTAL_NODES=$(kubectl get nodes \
        --no-headers 2>/dev/null |
        wc -l)

    READY_NODES=$(kubectl get nodes \
        --no-headers 2>/dev/null |
        awk '$2 == "Ready" {count++} END {print count+0}')

    echo "Nodes: $READY_NODES/$TOTAL_NODES Ready"

    if [ "$TOTAL_NODES" -gt 0 ] &&
       [ "$READY_NODES" -eq "$TOTAL_NODES" ]; then

        echo
        echo "Todos os Nodes estão Ready."
        break

    fi

    sleep 5

done

echo

# ============================================================
# Aguardar CoreDNS
# ============================================================

echo "[9/10] Aguardando CoreDNS..."

for i in {1..36}; do

    TOTAL_DNS=$(kubectl get pods \
        -n kube-system \
        -l k8s-app=kube-dns \
        --no-headers 2>/dev/null |
        wc -l)

    READY_DNS=$(kubectl get pods \
        -n kube-system \
        -l k8s-app=kube-dns \
        --no-headers 2>/dev/null |
        awk '$2 == "1/1" && $3 == "Running" {count++} END {print count+0}')

    echo "CoreDNS: $READY_DNS/$TOTAL_DNS Ready"

    if [ "$TOTAL_DNS" -gt 0 ] &&
       [ "$READY_DNS" -eq "$TOTAL_DNS" ]; then

        echo
        echo "CoreDNS : Ready"
        break

    fi

    sleep 5

done

# ============================================================
# Validação final
# ============================================================

echo
echo "[10/10] Validação final..."
echo

echo "============================================================"
echo " FLANNEL"
echo "============================================================"

echo
echo "Pods do Flannel:"
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
echo "CoreDNS:"
kubectl get pods \
    -n kube-system \
    -l k8s-app=kube-dns

echo

# ============================================================
# Resultado
# ============================================================

READY_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null |
    awk '$2 == "Ready" {count++} END {print count+0}')

TOTAL_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null |
    wc -l)

FLANNEL_RUNNING=$(kubectl get pods \
    -n "$FLANNEL_NAMESPACE" \
    --no-headers 2>/dev/null |
    awk '$3 == "Running" {count++} END {print count+0}')

FLANNEL_DESIRED=$(kubectl get daemonset kube-flannel-ds \
    -n "$FLANNEL_NAMESPACE" \
    -o jsonpath='{.status.desiredNumberScheduled}')

echo "============================================================"
echo " RESULTADO"
echo "============================================================"
echo

echo "Nodes:"
echo "  Ready   : $READY_NODES"
echo "  Total   : $TOTAL_NODES"
echo

echo "Flannel:"
echo "  Running : $FLANNEL_RUNNING"
echo "  Desired : $FLANNEL_DESIRED"
echo

if [ "$READY_NODES" -eq "$TOTAL_NODES" ] &&
   [ "$FLANNEL_RUNNING" -eq "$FLANNEL_DESIRED" ] &&
   [ "$FLANNEL_DESIRED" -gt 0 ]; then

    echo "============================================================"
    echo " FLANNEL CONFIGURADO COM SUCESSO"
    echo "============================================================"
    echo
    echo "Namespace : $FLANNEL_NAMESPACE"
    echo "Pod CIDR  : $EXPECTED_POD_CIDR"
    echo "CNI       : Flannel"
    echo
    echo "Node       : Ready"
    echo "CoreDNS    : Running"
    echo "Networking : Ready"
    echo
    echo "Próxima etapa:"
    echo "  Adicionar os Workers ao cluster."
    echo

else

    echo "============================================================"
    echo " ATENÇÃO: CLUSTER AINDA NÃO ESTÁ COMPLETAMENTE READY"
    echo "============================================================"
    echo

    echo "Diagnóstico:"
    kubectl get nodes -o wide

    echo
    kubectl get pods -n "$FLANNEL_NAMESPACE" -o wide

    echo
    kubectl get pods -n kube-system -l k8s-app=kube-dns

    exit 1

fi