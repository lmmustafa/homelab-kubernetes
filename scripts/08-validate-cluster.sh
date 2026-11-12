#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/kubernetes.env"

PASS=0
FAIL=0

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}[OK]${NC} $1"
    ((PASS+=1))
}

fail() {
    echo -e "${RED}[FALHA]${NC} $1"
    ((FAIL+=1))
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Carrega configuração
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Arquivo de configuração não encontrado: $CONFIG_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Valida variáveis obrigatórias
REQUIRED_VARS=(
    KUBERNETES_VERSION
    CONTROL_PLANE_HOSTNAME
    WORKER_HOSTNAME
    METALLB_NAMESPACE
    IP_POOL_NAME
    L2_ADVERTISEMENT_NAME
)

for VAR in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!VAR:-}" ]]; then
        echo "Variável obrigatória ausente: $VAR"
        exit 1
    fi
done

# Define kubeconfig
if [[ -z "${KUBECONFIG:-}" ]]; then
    if [[ -f "$HOME/.kube/config" ]]; then
        export KUBECONFIG="$HOME/.kube/config"
    elif [[ -f /etc/kubernetes/admin.conf ]]; then
        export KUBECONFIG=/etc/kubernetes/admin.conf
    fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl não encontrado."
    exit 1
fi

EXPECTED_VERSION="v${KUBERNETES_VERSION}"

echo
echo "=========================================="
echo "       VALIDAÇÃO DO CLUSTER KUBERNETES"
echo "=========================================="
echo "Versão esperada: $EXPECTED_VERSION"
echo "Control Plane:   $CONTROL_PLANE_HOSTNAME"
echo "Worker:          $WORKER_HOSTNAME"
echo

# 1. API Server
info "Verificando API Server..."

if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    pass "API Server está respondendo e pronto."
else
    fail "API Server indisponível ou não está pronto."
fi

# 2. Nós e versões
info "Verificando nós do cluster..."

for NODE in "$CONTROL_PLANE_HOSTNAME" "$WORKER_HOSTNAME"; do
    if ! kubectl get node "$NODE" >/dev/null 2>&1; then
        fail "Nó $NODE não encontrado."
        continue
    fi

    NODE_READY="$(kubectl get node "$NODE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"

    NODE_VERSION="$(kubectl get node "$NODE" \
        -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"

    if [[ "$NODE_READY" == "True" ]]; then
        pass "Nó $NODE está Ready."
    else
        fail "Nó $NODE não está Ready (estado: ${NODE_READY:-desconhecido})."
    fi

    if [[ "$NODE_VERSION" == "$EXPECTED_VERSION" ]]; then
        pass "Nó $NODE utiliza Kubernetes $NODE_VERSION."
    else
        fail "Versão incorreta em $NODE: ${NODE_VERSION:-desconhecida}."
    fi
done

# 3. Flannel
info "Verificando Flannel..."

FLANNEL_DESIRED="$(kubectl -n kube-flannel get daemonset kube-flannel-ds \
    -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"

FLANNEL_READY="$(kubectl -n kube-flannel get daemonset kube-flannel-ds \
    -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"

if [[ "$FLANNEL_DESIRED" =~ ^[0-9]+$ ]] &&
   [[ "$FLANNEL_READY" =~ ^[0-9]+$ ]] &&
   (( FLANNEL_DESIRED > 0 && FLANNEL_READY == FLANNEL_DESIRED )); then
    pass "Flannel está pronto em todos os nós previstos ($FLANNEL_READY/$FLANNEL_DESIRED)."
else
    fail "Flannel não está totalmente pronto ($FLANNEL_READY/$FLANNEL_DESIRED)."
fi

# 4. CoreDNS
info "Verificando CoreDNS..."

COREDNS_DESIRED="$(kubectl -n kube-system get deployment coredns \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)"

COREDNS_READY="$(kubectl -n kube-system get deployment coredns \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"

COREDNS_READY="${COREDNS_READY:-0}"

if [[ "$COREDNS_DESIRED" =~ ^[0-9]+$ ]] &&
   [[ "$COREDNS_READY" =~ ^[0-9]+$ ]] &&
   (( COREDNS_DESIRED > 0 && COREDNS_READY == COREDNS_DESIRED )); then
    pass "CoreDNS está pronto ($COREDNS_READY/$COREDNS_DESIRED)."
else
    fail "CoreDNS não está totalmente pronto ($COREDNS_READY/$COREDNS_DESIRED)."
fi

# 5. MetalLB Controller
info "Verificando MetalLB Controller..."

METALLB_CONTROLLER_DESIRED="$(kubectl -n "$METALLB_NAMESPACE" get deployment controller \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)"

METALLB_CONTROLLER_READY="$(kubectl -n "$METALLB_NAMESPACE" get deployment controller \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"

METALLB_CONTROLLER_READY="${METALLB_CONTROLLER_READY:-0}"

if [[ "$METALLB_CONTROLLER_DESIRED" =~ ^[0-9]+$ ]] &&
   [[ "$METALLB_CONTROLLER_READY" =~ ^[0-9]+$ ]] &&
   (( METALLB_CONTROLLER_DESIRED > 0 &&
      METALLB_CONTROLLER_READY == METALLB_CONTROLLER_DESIRED )); then
    pass "MetalLB Controller está pronto."
else
    fail "MetalLB Controller não está pronto."
fi

# 6. MetalLB Speaker
info "Verificando MetalLB Speaker..."

METALLB_SPEAKER_DESIRED="$(kubectl -n "$METALLB_NAMESPACE" get daemonset speaker \
    -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"

METALLB_SPEAKER_READY="$(kubectl -n "$METALLB_NAMESPACE" get daemonset speaker \
    -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"

if [[ "$METALLB_SPEAKER_DESIRED" =~ ^[0-9]+$ ]] &&
   [[ "$METALLB_SPEAKER_READY" =~ ^[0-9]+$ ]] &&
   (( METALLB_SPEAKER_DESIRED > 0 &&
      METALLB_SPEAKER_READY == METALLB_SPEAKER_DESIRED )); then
    pass "MetalLB Speaker está pronto em todos os nós previstos."
else
    fail "MetalLB Speaker não está totalmente pronto ($METALLB_SPEAKER_READY/$METALLB_SPEAKER_DESIRED)."
fi

# 7. Recursos de configuração do MetalLB
info "Verificando recursos do MetalLB..."

if kubectl -n "$METALLB_NAMESPACE" get ipaddresspool "$IP_POOL_NAME" \
    >/dev/null 2>&1; then
    pass "IPAddressPool $IP_POOL_NAME encontrado."
else
    fail "IPAddressPool $IP_POOL_NAME não encontrado."
fi

if kubectl -n "$METALLB_NAMESPACE" get l2advertisement "$L2_ADVERTISEMENT_NAME" \
    >/dev/null 2>&1; then
    pass "L2Advertisement $L2_ADVERTISEMENT_NAME encontrado."
else
    fail "L2Advertisement $L2_ADVERTISEMENT_NAME não encontrado."
fi

# Resultado
echo
echo "=========================================="
echo "             RESULTADO FINAL"
echo "=========================================="
echo -e "${GREEN}Verificações aprovadas: $PASS${NC}"
echo -e "${RED}Verificações com falha: $FAIL${NC}"
echo

if (( FAIL > 0 )); then
    echo "Cluster precisa de atenção. Consulte as falhas acima."
    exit 1
fi

echo "Cluster validado com sucesso."
exit 0
