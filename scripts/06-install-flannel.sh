#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação e validação do Flannel
# Executar exclusivamente no Control Plane
# ============================================================

# Verificar root
if [[ "$EUID" -ne 0 ]]; then
    echo "ERRO: execute como root."
    echo "Exemplo: sudo ./scripts/06-install-flannel.sh"
    exit 1
fi

# ============================================================
# Carregar configuração central
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/config/kubernetes.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERRO: configuração não encontrada: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

: "${KUBERNETES_VERSION:?KUBERNETES_VERSION não definida}"
: "${CONTROL_PLANE_IP:?CONTROL_PLANE_IP não definida}"
: "${CONTROL_PLANE_HOSTNAME:?CONTROL_PLANE_HOSTNAME não definido}"
: "${POD_NETWORK_CIDR:?POD_NETWORK_CIDR não definida}"

FLANNEL_VERSION="v0.28.10"
FLANNEL_NAMESPACE="kube-flannel"
FLANNEL_DS="kube-flannel-ds"

FLANNEL_MANIFEST_URL="https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml"

# ============================================================
# Cabeçalho
# ============================================================

echo
echo "============================================================"
echo " INSTALAÇÃO DO FLANNEL"
echo "============================================================"
echo
echo "Control Plane : $CONTROL_PLANE_HOSTNAME"
echo "IP            : $CONTROL_PLANE_IP"
echo "Kubernetes    : v$KUBERNETES_VERSION"
echo "Flannel       : $FLANNEL_VERSION"
echo "Pod CIDR      : $POD_NETWORK_CIDR"
echo

# ============================================================
# 1. Validar hostname e IP
# ============================================================

echo "[1/9] Validando Control Plane..."

if [[ "$(hostname)" != "$CONTROL_PLANE_HOSTNAME" ]]; then
    echo "ERRO: hostname incorreto."
    exit 1
fi

if ! ip -o -4 addr show |
    awk '{print $4}' |
    cut -d/ -f1 |
    grep -Fxq "$CONTROL_PLANE_IP"; then
    echo "ERRO: IP $CONTROL_PLANE_IP não encontrado."
    exit 1
fi

echo "Hostname e IP: OK"

# ============================================================
# 2. Configurar KUBECONFIG
# ============================================================

echo
echo "[2/9] Configurando acesso ao Kubernetes..."

if [[ -z "${KUBECONFIG:-}" ]]; then
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
        echo "ERRO: /etc/kubernetes/admin.conf não encontrado."
        echo "Inicialize primeiro o Control Plane."
        exit 1
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf
fi

echo "KUBECONFIG: $KUBECONFIG"

# ============================================================
# 3. Validar API Server
# ============================================================

echo
echo "[3/9] Verificando Kubernetes API..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERRO: Kubernetes API indisponível."
    exit 1
fi

kubectl get nodes -o wide

# ============================================================
# 4. Validar Pod CIDR
# ============================================================

echo
echo "[4/9] Validando Pod CIDR dos Nodes..."

NODE_POD_CIDRS="$(
    kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.podCIDR}{"\n"}{end}'
)"

if [[ -z "$NODE_POD_CIDRS" ]]; then
    echo "ERRO: nenhum Node encontrado."
    exit 1
fi

printf '%s\n' "$NODE_POD_CIDRS"

python3 - "$POD_NETWORK_CIDR" "$NODE_POD_CIDRS" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1])
entries = sys.argv[2].strip().splitlines()

for entry in entries:
    parts = entry.split()

    if len(parts) != 2 or not parts[1]:
        print(f"ERRO: Pod CIDR ausente: {entry}")
        sys.exit(1)

    node, cidr = parts

    try:
        node_network = ipaddress.ip_network(cidr)
    except ValueError:
        print(f"ERRO: CIDR inválido no Node {node}: {cidr}")
        sys.exit(1)

    if not node_network.subnet_of(network):
        print(f"ERRO: {cidr} do Node {node} está fora de {network}")
        sys.exit(1)

    print(f"Node {node}: Pod CIDR válido")

PY

echo "Pod CIDR: OK"

# ============================================================
# 5. Baixar manifesto oficial
# ============================================================

echo
echo "[5/9] Baixando manifesto oficial..."

TEMP_MANIFEST="$(mktemp)"
trap 'rm -f "$TEMP_MANIFEST"' EXIT

if ! curl -fsSL "$FLANNEL_MANIFEST_URL" -o "$TEMP_MANIFEST"; then
    echo "ERRO: não foi possível baixar o manifesto."
    exit 1
fi

if ! grep -q 'kind: DaemonSet' "$TEMP_MANIFEST"; then
    echo "ERRO: manifesto inválido."
    exit 1
fi

# Ajustar a rede do manifesto conforme configuração central.
python3 - "$TEMP_MANIFEST" "$POD_NETWORK_CIDR" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
cidr = sys.argv[2]

content = path.read_text()
old = 'Network: "10.244.0.0/16"'

if old not in content:
    print("ERRO: configuração Network esperada não encontrada.")
    sys.exit(1)

content = content.replace(old, f'Network: "{cidr}"', 1)
path.write_text(content)

if f'Network: "{cidr}"' not in content:
    print("ERRO: não foi possível validar o Pod CIDR no manifesto.")
    sys.exit(1)

print(f"Manifesto preparado com Pod CIDR {cidr}")
PY

# ============================================================
# 6. Aplicar Flannel
# ============================================================

echo
echo "[6/9] Aplicando manifesto do Flannel..."

kubectl apply -f "$TEMP_MANIFEST"

echo "Manifesto aplicado."

# ============================================================
# 7. Aguardar DaemonSet e Nodes
# ============================================================

echo
echo "[7/9] Aguardando DaemonSet do Flannel..."

kubectl rollout status \
    "daemonset/$FLANNEL_DS" \
    -n "$FLANNEL_NAMESPACE" \
    --timeout=180s

echo
echo "Aguardando Pods do Flannel..."

kubectl wait \
    --for=condition=Ready \
    pod \
    -l app=flannel \
    -n "$FLANNEL_NAMESPACE" \
    --timeout=180s

echo
echo "Aguardando Nodes Ready..."

kubectl wait \
    --for=condition=Ready \
    nodes \
    --all \
    --timeout=180s

# ============================================================
# 8. Aguardar CoreDNS
# ============================================================

echo
echo "[8/9] Aguardando CoreDNS..."

kubectl rollout status \
    deployment/coredns \
    -n kube-system \
    --timeout=180s

# ============================================================
# 9. Validação final
# ============================================================

echo
echo "[9/9] Validando componentes..."

DS_STATUS="$(
    kubectl get daemonset "$FLANNEL_DS" \
        -n "$FLANNEL_NAMESPACE" \
        -o jsonpath='{.status.desiredNumberScheduled} {.status.numberReady}'
)"

read -r FLANNEL_DESIRED FLANNEL_READY <<< "$DS_STATUS"

if [[ "$FLANNEL_DESIRED" -eq 0 ||
      "$FLANNEL_READY" -ne "$FLANNEL_DESIRED" ]]; then
    echo "ERRO: Flannel não está completamente Ready."
    exit 1
fi

DNS_STATUS="$(
    kubectl get deployment coredns \
        -n kube-system \
        -o jsonpath='{.spec.replicas} {.status.readyReplicas}'
)"

read -r DNS_DESIRED DNS_READY <<< "$DNS_STATUS"

DNS_READY="${DNS_READY:-0}"

if [[ "$DNS_DESIRED" -eq 0 ||
      "$DNS_READY" -ne "$DNS_DESIRED" ]]; then
    echo "ERRO: CoreDNS não está completamente Ready."
    exit 1
fi

echo
echo "Pods Flannel:"
kubectl get pods -n "$FLANNEL_NAMESPACE" -o wide

echo
echo "DaemonSet:"
kubectl get daemonset "$FLANNEL_DS" -n "$FLANNEL_NAMESPACE"

echo
echo "CoreDNS:"
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo
echo "Nodes:"
kubectl get nodes -o wide

# ============================================================
# Resultado
# ============================================================

echo
echo "============================================================"
echo " FLANNEL CONFIGURADO COM SUCESSO"
echo "============================================================"
echo
echo "Kubernetes : v$KUBERNETES_VERSION"
echo "Flannel    : $FLANNEL_VERSION"
echo "Pod CIDR   : $POD_NETWORK_CIDR"
echo "DaemonSet  : $FLANNEL_READY/$FLANNEL_DESIRED Ready"
echo "CoreDNS    : $DNS_READY/$DNS_DESIRED Ready"
echo
echo "Próxima etapa:"
echo "  Instalar o MetalLB."
echo
