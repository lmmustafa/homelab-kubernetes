#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação do Kubernetes
# Homelab Kubernetes
# ============================================================
#
# Instala:
#   kubeadm
#   kubelet
#   kubectl
#
# Executar nos dois nós:
#   s0076-kubernetes-master-prd
#   s0077-kubernetes-worker-prd
#
# Uso:
#   sudo ./03-install-kubernetes.sh
#
# ============================================================

# ============================================================
# Verificar root
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERRO: execute este script como root."
    echo "Exemplo: sudo ./03-install-kubernetes.sh"
    exit 1
fi


# ============================================================
# Carregar configuração central
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/config/kubernetes.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERRO: arquivo de configuração não encontrado:"
    echo "$CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

: "${KUBERNETES_VERSION:?KUBERNETES_VERSION não definida}"
: "${POD_NETWORK_CIDR:?POD_NETWORK_CIDR não definida}"
: "${SERVICE_CIDR:?SERVICE_CIDR não definida}"

KUBERNETES_MINOR_VERSION="v${KUBERNETES_VERSION%.*}"
KUBERNETES_REPO="https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR_VERSION}/deb/"

KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
REPOSITORY_FILE="/etc/apt/sources.list.d/kubernetes.list"
CONTAINERD_CONFIG="/etc/containerd/config.toml"

echo
echo "============================================================"
echo " Instalação do Kubernetes"
echo "============================================================"
echo

# ============================================================
# Informações do sistema
# ============================================================

echo "Hostname       : $(hostname)"
echo "Kubernetes     : ${KUBERNETES_VERSION}"
echo "Repositório    : ${KUBERNETES_MINOR_VERSION}"
echo "Kernel         : $(uname -r)"
echo "OS             : $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "Pod CIDR       : ${POD_NETWORK_CIDR}"
echo "Service CIDR   : ${SERVICE_CIDR}"
echo

# ============================================================
# Validar Swap
# ============================================================

echo "[1/8] Validando Swap..."

if swapon --show --noheadings | grep -q .; then
    echo "ERRO: Swap está habilitado."
    echo "Execute novamente o prepare-node.sh."
    exit 1
fi

echo "Swap: desabilitado"
echo

# ============================================================
# Validar containerd
# ============================================================

echo "[2/8] Validando containerd..."

if ! command -v containerd >/dev/null 2>&1; then
    echo "ERRO: containerd não está instalado."
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    echo "ERRO: containerd não está ativo."
    exit 1
fi

containerd --version
echo "containerd: ativo"
echo

# ============================================================
# Validar SystemdCgroup na seção correta
# ============================================================

echo "Validando SystemdCgroup..."

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

echo "SystemdCgroup: true"
echo

# ============================================================
# Instalar dependências
# ============================================================

echo "[3/8] Instalando dependências..."

apt-get update

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gpg

echo

# ============================================================
# Configurar keyring
# ============================================================

echo "[4/8] Configurando chave do repositório Kubernetes..."

install -d -m 755 /etc/apt/keyrings

TEMP_KEY="$(mktemp)"

trap 'rm -f "$TEMP_KEY"' EXIT

curl -fsSL "${KUBERNETES_REPO}Release.key" |
    gpg --dearmor > "$TEMP_KEY"

install -m 644 "$TEMP_KEY" "$KEYRING"

echo "Keyring configurado:"
echo "$KEYRING"
echo

# ============================================================
# Configurar repositório
# ============================================================

echo "[5/8] Configurando repositório Kubernetes..."

cat > "$REPOSITORY_FILE" <<EOF
deb [signed-by=${KEYRING}] ${KUBERNETES_REPO} /
EOF

chmod 644 "$REPOSITORY_FILE"

cat "$REPOSITORY_FILE"
echo

# ============================================================
# Atualizar APT
# ============================================================

echo "[6/8] Atualizando índice de pacotes..."

apt-get update

echo

# ============================================================
# Identificar versões exatas disponíveis
# ============================================================

echo "[7/8] Verificando versões disponíveis..."

get_package_version() {
    local package="$1"
    local candidate

    candidate="$(apt-cache policy "$package" |
        awk '/Candidate:/ {print $2; exit}')"

    if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
        echo "ERRO: pacote ${package} não encontrado."
        return 1
    fi

    if [[ "$candidate" != "${KUBERNETES_VERSION}-"* ]]; then
        echo "ERRO: versão esperada ${KUBERNETES_VERSION} para ${package}."
        echo "Versão candidata encontrada: ${candidate}"
        return 1
    fi

    printf '%s' "$candidate"
}

KUBELET_PACKAGE_VERSION="$(get_package_version kubelet)"
KUBEADM_PACKAGE_VERSION="$(get_package_version kubeadm)"
KUBECTL_PACKAGE_VERSION="$(get_package_version kubectl)"

echo "kubelet : ${KUBELET_PACKAGE_VERSION}"
echo "kubeadm : ${KUBEADM_PACKAGE_VERSION}"
echo "kubectl : ${KUBECTL_PACKAGE_VERSION}"
echo

# ============================================================
# Instalar versões exatas
# ============================================================

echo "Instalando componentes Kubernetes..."

apt-get install -y \
    "kubelet=${KUBELET_PACKAGE_VERSION}" \
    "kubeadm=${KUBEADM_PACKAGE_VERSION}" \
    "kubectl=${KUBECTL_PACKAGE_VERSION}"

# ============================================================
# Validar versões dos binários
# ============================================================

EXPECTED_VERSION="v${KUBERNETES_VERSION}"

KUBEADM_VERSION="$(kubeadm version -o short)"
KUBELET_VERSION="$(kubelet --version | awk '{print $2}')"
KUBECTL_VERSION="$(kubectl version --client --output=yaml |
    awk '/^[[:space:]]*gitVersion:/ {print $2; exit}')"

echo
echo "Validando versões instaladas..."

for component in KUBEADM KUBELET KUBECTL; do
    variable="${component}_VERSION"
    actual="${!variable}"

    echo "${component}: ${actual}"

    if [[ "$actual" != "$EXPECTED_VERSION" ]]; then
        echo "ERRO: versão incorreta em ${component}."
        echo "Esperada: ${EXPECTED_VERSION}"
        exit 1
    fi
done

# ============================================================
# Fixar versões
# ============================================================

echo
echo "Fixando pacotes Kubernetes..."

apt-mark hold kubelet kubeadm kubectl

# ============================================================
# Habilitar kubelet
# ============================================================

echo
echo "Habilitando kubelet..."

systemctl enable kubelet

# ============================================================
# Validação final
# ============================================================

echo
echo "[8/8] Validação final..."

echo
echo "============================================================"
echo " Validação Final"
echo "============================================================"

echo
echo "Hostname:"
hostnamectl --static

echo
echo "Kubernetes:"
echo "kubeadm : ${KUBEADM_VERSION}"
echo "kubelet : ${KUBELET_VERSION}"
echo "kubectl : ${KUBECTL_VERSION}"

echo
echo "Pacotes instalados:"
dpkg-query -W -f='${binary:Package} ${Version}\n' \
    kubeadm kubelet kubectl

echo
echo "Pacotes marcados como hold:"
apt-mark showhold | grep -E '^(kubeadm|kubelet|kubectl)$'

echo
echo "Kubelet:"
systemctl is-enabled kubelet

echo
echo "Containerd:"
systemctl is-active containerd

echo
echo "SystemdCgroup:"
grep -E '^[[:space:]]*SystemdCgroup[[:space:]]*=' \
    "$CONTAINERD_CONFIG"

echo
echo "============================================================"
echo " KUBERNETES INSTALADO COM SUCESSO"
echo "============================================================"

echo
echo "Versão: ${KUBERNETES_VERSION}"
echo
echo "Próxima etapa:"
echo "Inicialização do Control Plane com kubeadm init"
echo
