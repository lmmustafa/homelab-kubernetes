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
# Executar nos três nós:
#   k8s-master-01
#   k8s-worker-01
#   k8s-worker-02
#
# Uso:
#   sudo ./install-kubernetes.sh
#
# ============================================================

KUBERNETES_VERSION="v1.36"

KUBERNETES_REPO="https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/"
KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
REPOSITORY_FILE="/etc/apt/sources.list.d/kubernetes.list"

echo
echo "============================================================"
echo " Instalação do Kubernetes"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute este script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./install-kubernetes.sh"
    exit 1
fi

# ============================================================
# Informações do sistema
# ============================================================

HOSTNAME_CURRENT=$(hostname)

echo "Hostname       : $HOSTNAME_CURRENT"
echo "Kubernetes     : $KUBERNETES_VERSION"
echo "Kernel         : $(uname -r)"
echo "OS             : $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)"
echo

# ============================================================
# Validar Swap
# ============================================================

echo "[1/8] Validando Swap..."

if swapon --show | grep -q .; then
    echo "ERRO: Swap está habilitado."
    echo
    echo "Execute novamente o prepare-node.sh antes de continuar."
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
    echo
    echo "Execute primeiro:"
    echo "  install-containerd.sh"
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    echo "ERRO: containerd não está ativo."
    exit 1
fi

echo "containerd: ativo"
containerd --version

echo

# ============================================================
# Validar SystemdCgroup
# ============================================================

echo "Validando SystemdCgroup..."

CONTAINERD_CONFIG="/etc/containerd/config.toml"

if [ ! -f "$CONTAINERD_CONFIG" ]; then
    echo "ERRO: configuração do containerd não encontrada."
    exit 1
fi

if ! grep -qE '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true' \
    "$CONTAINERD_CONFIG"; then

    echo "ERRO: SystemdCgroup não está configurado como true."
    exit 1
fi

echo "SystemdCgroup: true"
echo

# ============================================================
# Instalar dependências do repositório
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

mkdir -p -m 755 /etc/apt/keyrings

if [ -f "$KEYRING" ]; then
    echo "Keyring existente encontrado."
else
    curl -fsSL \
        "${KUBERNETES_REPO}Release.key" |
        gpg --dearmor -o "$KEYRING"
fi

chmod 644 "$KEYRING"

echo "Keyring:"
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

echo
echo "Repositório configurado:"
cat "$REPOSITORY_FILE"

echo

# ============================================================
# Atualizar APT
# ============================================================

echo "[6/8] Atualizando índice de pacotes..."

apt-get update

echo

# ============================================================
# Instalar Kubernetes
# ============================================================

echo "[7/8] Instalando kubeadm, kubelet e kubectl..."

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

echo

# ============================================================
# Fixar versões
# ============================================================

echo "Fixando pacotes Kubernetes..."

apt-mark hold kubelet kubeadm kubectl

echo

# ============================================================
# Habilitar kubelet
# ============================================================

echo "Habilitando kubelet..."

systemctl enable kubelet

echo

# ============================================================
# Validação final
# ============================================================

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
echo "kubeadm:"
kubeadm version -o short

echo
echo "kubelet:"
kubelet --version

echo
echo "kubectl:"
kubectl version --client --output=yaml | grep gitVersion | head -n 1

echo

echo "Pacotes:"
dpkg -l | grep -E '^ii[[:space:]]+(kubeadm|kubelet|kubectl)[[:space:]]' || true

echo

echo "Pacotes marcados como hold:"
apt-mark showhold | grep -E '^(kubeadm|kubelet|kubectl)$' || true

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

echo "Componentes:"
echo "  kubeadm  : instalado"
echo "  kubelet  : instalado"
echo "  kubectl  : instalado"
echo
echo "Versão:"
echo "  $KUBERNETES_VERSION"
echo
echo "Próxima etapa:"
echo "  Inicialização do Control Plane com kubeadm init"
echo