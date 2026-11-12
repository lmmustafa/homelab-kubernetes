#!/bin/bash

set -Eeuo pipefail

# ============================================================
# MetalLB - Kubernetes Production
# Modo de anúncio: Layer 2
# ============================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/kubernetes.env"

# ============================================================
# Validar execução
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERRO: execute como root."
    echo "Uso: sudo bash scripts/07-install-metallb.sh"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERRO: configuração não encontrada: $CONFIG_FILE"
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${CONTROL_PLANE_HOSTNAME:?Variável não definida}"
: "${WORKER_HOSTNAME:?Variável não definida}"
: "${METALLB_NAMESPACE:?Variável não definida}"
: "${METALLB_IP_START:?Variável não definida}"
: "${METALLB_IP_END:?Variável não definida}"
: "${METALLB_NETWORK_CIDR:?Variável não definida}"
: "${IP_POOL_NAME:?Variável não definida}"
: "${L2_ADVERTISEMENT_NAME:?Variável não definida}"

: "${METALLB_VERSION:?Variável METALLB_VERSION não definida}"
METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

# ============================================================
# Configurar kubeconfig
# ============================================================

if [[ -z "${KUBECONFIG:-}" && -f /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
fi

echo
echo "============================================================"
echo " MetalLB - Kubernetes Production"
echo "============================================================"
echo

# ============================================================
# Validar dependências e acesso
# ============================================================

echo "[1/8] Validando dependências..."

command -v kubectl >/dev/null 2>&1 || {
    echo "ERRO: kubectl não encontrado."
    exit 1
}

command -v python3 >/dev/null 2>&1 || {
    echo "ERRO: python3 não encontrado."
    exit 1
}

kubectl cluster-info >/dev/null 2>&1 || {
    echo "ERRO: não foi possível acessar o cluster."
    exit 1
}

echo "kubectl: OK"
echo "Kubernetes API: OK"

# ============================================================
# Validar faixa de IP
# ============================================================

echo
echo "[2/8] Validando faixa de endereços..."

python3 - "$METALLB_IP_START" "$METALLB_IP_END" "$METALLB_NETWORK_CIDR" <<'PY'
import ipaddress
import sys

start = ipaddress.ip_address(sys.argv[1])
end = ipaddress.ip_address(sys.argv[2])
network = ipaddress.ip_network(sys.argv[3], strict=False)

if start.version != 4 or end.version != 4:
    sys.exit("ERRO: MetalLB exige endereços IPv4 nesta configuração.")

if start not in network or end not in network:
    sys.exit(f"ERRO: faixa fora da rede {network}.")

if int(start) > int(end):
    sys.exit("ERRO: IP inicial maior que IP final.")

print(f"Rede: {network}")
print(f"Faixa: {start} - {end}")
print("Endereços: OK")
PY

# ============================================================
# Validar Nodes
# ============================================================

echo
echo "[3/8] Validando Nodes..."

for NODE in "$CONTROL_PLANE_HOSTNAME" "$WORKER_HOSTNAME"; do
    if ! kubectl get node "$NODE" >/dev/null 2>&1; then
        echo "ERRO: Node $NODE não encontrado."
        kubectl get nodes -o wide
        exit 1
    fi

    kubectl wait \
        --for=condition=Ready \
        "node/$NODE" \
        --timeout=120s
done

kubectl get nodes -o wide

# ============================================================
# Validar Flannel
# ============================================================

echo
echo "[4/8] Validando Flannel..."

kubectl get namespace kube-flannel >/dev/null 2>&1 || {
    echo "ERRO: namespace kube-flannel não encontrado."
    exit 1
}

FLANNEL_DS=()

while IFS= read -r DS; do
    [[ -n "$DS" ]] && FLANNEL_DS+=("$DS")
done < <(
    kubectl get daemonsets \
        -n kube-flannel \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

if [[ "${#FLANNEL_DS[@]}" -eq 0 ]]; then
    echo "ERRO: DaemonSet do Flannel não encontrado."
    exit 1
fi

for DS in "${FLANNEL_DS[@]}"; do
    kubectl rollout status \
        "daemonset/$DS" \
        -n kube-flannel \
        --timeout=180s
done

kubectl get daemonsets -n kube-flannel
kubectl get pods -n kube-flannel -o wide

# ============================================================
# Instalar MetalLB
# ============================================================

echo
echo "[5/8] Aplicando manifesto do MetalLB..."

kubectl apply -f "$METALLB_MANIFEST"

kubectl wait \
    --for=condition=Established \
    crd/ipaddresspools.metallb.io \
    --timeout=120s

kubectl wait \
    --for=condition=Established \
    crd/l2advertisements.metallb.io \
    --timeout=120s

# ============================================================
# Aguardar Controller e Speakers
# ============================================================

echo
echo "[6/8] Aguardando componentes do MetalLB..."

kubectl rollout status \
    deployment/controller \
    -n "$METALLB_NAMESPACE" \
    --timeout=180s

kubectl rollout status \
    daemonset/speaker \
    -n "$METALLB_NAMESPACE" \
    --timeout=180s

kubectl get pods -n "$METALLB_NAMESPACE" -o wide

# ============================================================
# Configurar IPAddressPool
# ============================================================

echo
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

# ============================================================
# Configurar L2Advertisement
# ============================================================

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

# ============================================================
# Validação final
# ============================================================

echo
echo "[8/8] Validação final..."

kubectl get nodes -o wide

echo
echo "MetalLB Pods:"
kubectl get pods -n "$METALLB_NAMESPACE" -o wide

echo
echo "IPAddressPool:"
kubectl get ipaddresspool \
    "$IP_POOL_NAME" \
    -n "$METALLB_NAMESPACE"

echo
echo "L2Advertisement:"
kubectl get l2advertisement \
    "$L2_ADVERTISEMENT_NAME" \
    -n "$METALLB_NAMESPACE"

echo
echo "============================================================"
echo " METALLB CONFIGURADO"
echo "============================================================"
echo
echo "Versão       : ${METALLB_VERSION}"
echo "Modo         : Layer 2"
echo "Namespace    : ${METALLB_NAMESPACE}"
echo "IP Pool      : ${METALLB_IP_START} - ${METALLB_IP_END}"
echo "Control Plane: ${CONTROL_PLANE_HOSTNAME}"
echo "Worker       : ${WORKER_HOSTNAME}"
echo
echo "Próxima etapa: testar um Service do tipo LoadBalancer."
