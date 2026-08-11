#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação e configuração do MetalLB
# Homelab Kubernetes
# ============================================================
#
# Kubernetes:
#   v1.36.3
#
# CNI:
#   Flannel
#
# MetalLB:
#   Layer 2
#
# Pool:
#   10.10.1.150 - 10.10.1.170
#
# Uso:
#   sudo ./install-metallb.sh
#
# Executar no k8s-master-01
#
# ============================================================

METALLB_NAMESPACE="metallb-system"

METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml"

METALLB_IP_START="10.10.1.150"
METALLB_IP_END="10.10.1.170"

IP_POOL_NAME="homelab-pool"
L2_ADVERTISEMENT_NAME="homelab-l2"

echo
echo "============================================================"
echo " Instalação e Configuração do MetalLB"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute o script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./install-metallb.sh"
    exit 1
fi

# ============================================================
# Verificar kubectl
# ============================================================

echo "[1/8] Validando kubectl..."

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERRO: kubectl não encontrado."
    exit 1
fi

echo "kubectl: OK"
echo

# ============================================================
# Validar acesso ao cluster
# ============================================================

echo "[2/8] Validando acesso ao cluster..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERRO: não foi possível acessar o Kubernetes."
    echo
    echo "Verifique:"
    echo "  export KUBECONFIG=/etc/kubernetes/admin.conf"
    exit 1
fi

echo "Kubernetes API: OK"
echo

# ============================================================
# Validar Nodes
# ============================================================

echo "[3/8] Validando Nodes..."

READY_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null |
    awk '$2 == "Ready" {count++} END {print count+0}')

if [ "$READY_NODES" -lt 3 ]; then
    echo "ERRO: menos de 3 Nodes em estado Ready."
    echo
    kubectl get nodes -o wide
    exit 1
fi

kubectl get nodes -o wide

echo
echo "Nodes Ready: $READY_NODES"
echo

# ============================================================
# Validar Flannel
# ============================================================

echo "[4/8] Validando Flannel..."

if ! kubectl get namespace kube-flannel >/dev/null 2>&1; then
    echo "ERRO: namespace kube-flannel não encontrado."
    exit 1
fi

FLANNEL_RUNNING=$(kubectl get pods \
    -n kube-flannel \
    --no-headers 2>/dev/null |
    awk '$3 == "Running" {count++} END {print count+0}')

if [ "$FLANNEL_RUNNING" -lt 3 ]; then
    echo "ERRO: Flannel não está Running em todos os Nodes."
    echo
    kubectl get pods -n kube-flannel -o wide
    exit 1
fi

echo "Flannel: OK"
echo

# ============================================================
# Verificar se MetalLB já está instalado
# ============================================================

echo "[5/8] Verificando MetalLB..."

if kubectl get namespace "$METALLB_NAMESPACE" >/dev/null 2>&1; then

    echo "Namespace $METALLB_NAMESPACE já existe."

    if kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
        echo "MetalLB aparentemente já está instalado."
    else
        echo "Namespace existe, mas MetalLB parece incompleto."
    fi

else

    echo "MetalLB ainda não instalado."

fi

echo

# ============================================================
# Instalar MetalLB
# ============================================================

echo "[6/8] Instalando MetalLB..."

if ! kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then

    echo "Aplicando manifesto oficial do MetalLB:"
    echo
    echo "$METALLB_MANIFEST"
    echo

    kubectl apply -f "$METALLB_MANIFEST"

    echo
    echo "Manifesto aplicado."

else

    echo "CRD do MetalLB já existe."
    echo "Instalação será mantida."

fi

echo

# ============================================================
# Aguardar componentes
# ============================================================

echo "Aguardando componentes do MetalLB..."

kubectl wait \
    --namespace "$METALLB_NAMESPACE" \
    --for=condition=available \
    deployment/controller \
    --timeout=180s

echo

echo "Componentes:"
kubectl get pods -n "$METALLB_NAMESPACE" -o wide

echo

# ============================================================
# Criar IPAddressPool
# ============================================================

echo "[7/8] Configurando IPAddressPool..."

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ${IP_POOL_NAME}
  namespace: ${METALLB_NAMESPACE}
spec:
  addresses:
    - ${METALLB_IP_START}-${METALLB_IP_END}
EOF

echo
echo "IPAddressPool configurado:"
echo
kubectl get ipaddresspool \
    -n "$METALLB_NAMESPACE"

echo

# ============================================================
# Criar L2Advertisement
# ============================================================

echo "Configurando L2Advertisement..."

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${L2_ADVERTISEMENT_NAME}
  namespace: ${METALLB_NAMESPACE}
spec:
  ipAddressPools:
    - ${IP_POOL_NAME}
EOF

echo
echo "L2Advertisement configurado:"
echo
kubectl get l2advertisement \
    -n "$METALLB_NAMESPACE"

echo

# ============================================================
# Validação final
# ============================================================

echo "[8/8] Validação final..."

echo
echo "============================================================"
echo " VALIDAÇÃO METALLB"
echo "============================================================"
echo

echo "Namespace:"
kubectl get namespace "$METALLB_NAMESPACE"

echo
echo "Pods:"
kubectl get pods \
    -n "$METALLB_NAMESPACE" \
    -o wide

echo
echo "IPAddressPool:"
kubectl get ipaddresspool \
    -n "$METALLB_NAMESPACE"

echo
echo "L2Advertisement:"
kubectl get l2advertisement \
    -n "$METALLB_NAMESPACE"

echo
echo "CRDs:"
kubectl get crd | grep metallb

echo
echo "============================================================"
echo " METALLB CONFIGURADO COM SUCESSO"
echo "============================================================"
echo

echo "Modo          : Layer 2"
echo "Pool          : ${METALLB_IP_START}-${METALLB_IP_END}"
echo "Namespace     : ${METALLB_NAMESPACE}"
echo
echo "Próxima etapa:"
echo
echo "  Criar um Service do tipo LoadBalancer"
echo "  e validar a atribuição de um IP da faixa MetalLB."
echo