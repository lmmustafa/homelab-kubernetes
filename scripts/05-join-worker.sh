#!/bin/bash

set -euo pipefail

# ============================================================
# Integração do Worker ao cluster Kubernetes
# ============================================================

# Verificar root
if [[ "$EUID" -ne 0 ]]; then
    echo "ERRO: execute este script como root."
    echo "Exemplo: sudo ./scripts/05-join-worker.sh"
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
: "${WORKER_IP:?WORKER_IP não definida}"
: "${WORKER_HOSTNAME:?WORKER_HOSTNAME não definido}"

EXPECTED_VERSION="v${KUBERNETES_VERSION}"
CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_IP}:6443"
CRI_SOCKET="unix:///var/run/containerd/containerd.sock"

# ============================================================
# Cabeçalho
# ============================================================

echo
echo "============================================================"
echo " Integração do Worker ao Kubernetes"
echo "============================================================"
echo
echo "Hostname esperado : $WORKER_HOSTNAME"
echo "IP esperado       : $WORKER_IP"
echo "Control Plane     : $CONTROL_PLANE_ENDPOINT"
echo "Kubernetes        : $EXPECTED_VERSION"
echo

# ============================================================
# Validar hostname
# ============================================================

echo "[1/8] Validando hostname..."

CURRENT_HOSTNAME="$(hostname)"

if [[ "$CURRENT_HOSTNAME" != "$WORKER_HOSTNAME" ]]; then
    echo "ERRO: hostname incorreto."
    echo "Atual   : $CURRENT_HOSTNAME"
    echo "Esperado: $WORKER_HOSTNAME"
    exit 1
fi

echo "Hostname: OK"

# ============================================================
# Validar IP
# ============================================================

echo
echo "[2/8] Validando endereço IP..."

if ! ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$WORKER_IP"; then
    echo "ERRO: IP $WORKER_IP não encontrado neste servidor."
    exit 1
fi

echo "IP: OK"

# ============================================================
# Validar swap
# ============================================================

echo
echo "[3/8] Validando swap..."

if swapon --noheadings --show | grep -q .; then
    echo "ERRO: swap está habilitado."
    echo "Execute: swapoff -a"
    exit 1
fi

echo "Swap: desabilitado"

# ============================================================
# Validar containerd
# ============================================================

echo
echo "[4/8] Validando containerd..."

if ! systemctl is-active --quiet containerd; then
    echo "ERRO: containerd não está ativo."
    exit 1
fi

CONTAINERD_CONFIG="/etc/containerd/config.toml"

if [[ ! -f "$CONTAINERD_CONFIG" ]]; then
    echo "ERRO: configuração do containerd não encontrada."
    exit 1
fi

if ! awk '
    /^\[.*runtimes\.runc\.options\][[:space:]]*$/ {
        in_section=1
        next
    }

    /^\[/ {
        in_section=0
    }

    in_section && /^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true([[:space:]]*#.*)?[[:space:]]*$/ {
        found=1
    }

    END {
        exit !found
    }
' "$CONTAINERD_CONFIG"; then
    echo "ERRO: SystemdCgroup não está como true na seção runc.options."
    exit 1
fi

echo "Containerd: OK"
echo "SystemdCgroup: true"

# ============================================================
# Validar Kubernetes
# ============================================================

echo
echo "[5/8] Validando versões Kubernetes..."

for binary in kubeadm kubelet; do
    if ! command -v "$binary" >/dev/null 2>&1; then
        echo "ERRO: $binary não está instalado."
        exit 1
    fi

    INSTALLED_VERSION="$("$binary" --version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"

    if [[ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]]; then
        echo "ERRO: versão incorreta do $binary."
        echo "Instalada: $INSTALLED_VERSION"
        echo "Esperada : $EXPECTED_VERSION"
        exit 1
    fi

    echo "$binary: $INSTALLED_VERSION"
done

# ============================================================
# Validar se já foi integrado
# ============================================================

echo
echo "[6/8] Verificando integração anterior..."

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
    echo "ERRO: este Worker já possui kubelet.conf."
    echo "Não execute o join novamente."
    exit 1
fi

if [[ -f /etc/kubernetes/pki/ca.crt ]]; then
    echo "ERRO: certificado de cluster já encontrado."
    echo "Verifique o estado deste Worker antes de continuar."
    exit 1
fi

echo "Worker ainda não integrado."

# ============================================================
# Validar conectividade com Control Plane
# ============================================================

echo
echo "[7/8] Testando conectividade com Control Plane..."

if ! timeout 5 bash -c "echo > /dev/tcp/${CONTROL_PLANE_IP}/6443" 2>/dev/null; then
    echo "ERRO: não foi possível acessar ${CONTROL_PLANE_ENDPOINT}."
    echo "Verifique o Control Plane e a rede."
    exit 1
fi

echo "Porta TCP 6443: acessível"

# ============================================================
# Receber comando de integração
# ============================================================

echo
echo "============================================================"
echo " COMANDO kubeadm join"
echo "============================================================"
echo
echo "No Control Plane, execute:"
echo
echo "  sudo kubeadm token create --print-join-command"
echo
echo "Copie o comando completo e cole abaixo."
echo

read -r -p "Comando kubeadm join: " JOIN_COMMAND

read -r -a JOIN_ARGS <<< "$JOIN_COMMAND"

if [[ "${#JOIN_ARGS[@]}" -ne 7 ]]; then
    echo "ERRO: formato do comando inválido."
    exit 1
fi

if [[ "${JOIN_ARGS[0]}" != "kubeadm" ||
      "${JOIN_ARGS[1]}" != "join" ||
      "${JOIN_ARGS[2]}" != "$CONTROL_PLANE_ENDPOINT" ||
      "${JOIN_ARGS[3]}" != "--token" ||
      "${JOIN_ARGS[5]}" != "--discovery-token-ca-cert-hash" ]]; then
    echo "ERRO: comando não corresponde ao Control Plane esperado."
    exit 1
fi

TOKEN="${JOIN_ARGS[4]}"
CA_HASH="${JOIN_ARGS[6]:-}"


if [[ ! "$TOKEN" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ ]]; then
    echo "ERRO: formato do token inválido."
    exit 1
fi

if [[ ! "$CA_HASH" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    echo "ERRO: hash da CA inválido."
    exit 1
fi

echo
echo "Comando validado."
echo "Iniciando integração do Worker..."
echo

kubeadm join "$CONTROL_PLANE_ENDPOINT" \
    --token "$TOKEN" \
    --discovery-token-ca-cert-hash "$CA_HASH" \
    --cri-socket "$CRI_SOCKET" \
    --node-name "$WORKER_HOSTNAME"

# ============================================================
# Validar serviço kubelet
# ============================================================

echo
echo "Validando serviço kubelet..."

systemctl enable kubelet
systemctl is-active --quiet kubelet

echo "Kubelet: ativo"

# ============================================================
# Final
# ============================================================

echo
echo "============================================================"
echo " WORKER INTEGRADO COM SUCESSO"
echo "============================================================"
echo
echo "Hostname : $WORKER_HOSTNAME"
echo "IP       : $WORKER_IP"
echo "Versão   : $EXPECTED_VERSION"
echo
echo "No Control Plane, valide com:"
echo
echo "  kubectl get nodes -o wide"
echo
