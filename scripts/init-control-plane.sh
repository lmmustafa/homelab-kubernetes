#!/bin/bash

set -euo pipefail

# ============================================================
# Inicialização do Kubernetes Control Plane
# Homelab Kubernetes
# ============================================================
#
# Node:
#   k8s-master-01
#   10.10.1.241
#
# Kubernetes:
#   v1.36.3
#
# CNI:
#   Flannel
#
# Pod Network:
#   10.244.0.0/16
#
# Uso:
#   sudo ./init-control-plane.sh
#
# ============================================================

KUBERNETES_VERSION="v1.36.3"

CONTROL_PLANE_IP="10.10.1.241"
CONTROL_PLANE_HOSTNAME="k8s-master-01"

# Flannel
POD_NETWORK_CIDR="10.244.0.0/16"

# Kubernetes Services
SERVICE_CIDR="10.96.0.0/12"

# containerd CRI
CRI_SOCKET="unix:///var/run/containerd/containerd.sock"

KUBEADM_CONFIG="/etc/kubernetes/kubeadm-config.yaml"

CONTAINERD_CONFIG="/etc/containerd/config.toml"

echo
echo "============================================================"
echo " Inicialização do Kubernetes Control Plane"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute este script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./init-control-plane.sh"
    exit 1
fi

# ============================================================
# Informações do sistema
# ============================================================

CURRENT_HOSTNAME=$(hostname)

echo "Hostname        : $CURRENT_HOSTNAME"
echo "Kubernetes      : $KUBERNETES_VERSION"
echo "Control Plane   : $CONTROL_PLANE_IP"
echo "Pod Network     : $POD_NETWORK_CIDR"
echo "Service Network : $SERVICE_CIDR"
echo "CRI             : $CRI_SOCKET"
echo

# ============================================================
# Validar hostname
# ============================================================

echo "[1/10] Validando hostname..."

if [ "$CURRENT_HOSTNAME" != "$CONTROL_PLANE_HOSTNAME" ]; then

    echo "ERRO: hostname incorreto."
    echo
    echo "Atual   : $CURRENT_HOSTNAME"
    echo "Esperado: $CONTROL_PLANE_HOSTNAME"
    echo

    exit 1
fi

echo "Hostname: OK"
echo

# ============================================================
# Validar IP
# ============================================================

echo "[2/10] Validando endereço IP..."

if ! ip -4 addr show | grep -q "$CONTROL_PLANE_IP"; then

    echo "ERRO: IP $CONTROL_PLANE_IP não encontrado."
    echo

    ip -br addr

    exit 1
fi

echo "IP: $CONTROL_PLANE_IP"
echo

# ============================================================
# Validar Swap
# ============================================================

echo "[3/10] Validando Swap..."

if swapon --show | grep -q .; then

    echo "ERRO: Swap está habilitado."
    echo
    echo "Execute novamente:"
    echo
    echo "  prepare-node.sh"
    echo

    exit 1
fi

echo "Swap: OFF"
echo

# ============================================================
# Validar containerd
# ============================================================

echo "[4/10] Validando containerd..."

if ! command -v containerd >/dev/null 2>&1; then

    echo "ERRO: containerd não está instalado."
    exit 1

fi

if ! systemctl is-active --quiet containerd; then

    echo "ERRO: containerd não está ativo."
    systemctl status containerd --no-pager
    exit 1

fi

echo "containerd: ACTIVE"
containerd --version
echo

# ============================================================
# Validar SystemdCgroup
# ============================================================

echo "[5/10] Validando SystemdCgroup..."

if [ ! -f "$CONTAINERD_CONFIG" ]; then

    echo "ERRO: configuração do containerd não encontrada:"
    echo "$CONTAINERD_CONFIG"
    exit 1

fi

if ! grep -qE \
    '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true' \
    "$CONTAINERD_CONFIG"; then

    echo "ERRO: SystemdCgroup não está configurado como true."
    exit 1

fi

echo "SystemdCgroup: true"
echo

# ============================================================
# Validar kubeadm
# ============================================================

echo "[6/10] Validando kubeadm..."

if ! command -v kubeadm >/dev/null 2>&1; then

    echo "ERRO: kubeadm não está instalado."
    exit 1

fi

INSTALLED_VERSION=$(kubeadm version -o short)

echo "kubeadm: $INSTALLED_VERSION"

if [ "$INSTALLED_VERSION" != "$KUBERNETES_VERSION" ]; then

    echo "ERRO: versão incorreta do kubeadm."
    echo
    echo "Esperada: $KUBERNETES_VERSION"
    echo "Atual   : $INSTALLED_VERSION"
    exit 1

fi

echo "Versão: OK"
echo

# ============================================================
# Validar kubelet
# ============================================================

echo "[7/10] Validando kubelet..."

if ! command -v kubelet >/dev/null 2>&1; then

    echo "ERRO: kubelet não está instalado."
    exit 1

fi

KUBELET_VERSION=$(kubelet --version)

echo "$KUBELET_VERSION"

if ! echo "$KUBELET_VERSION" | grep -q "$KUBERNETES_VERSION"; then

    echo "ERRO: versão do kubelet diferente de $KUBERNETES_VERSION."
    exit 1

fi

echo "kubelet: OK"
echo

# ============================================================
# Verificar se Control Plane já existe
# ============================================================

echo "[8/10] Verificando estado do Control Plane..."

if [ -f "/etc/kubernetes/admin.conf" ]; then

    echo "ERRO: o Control Plane já foi inicializado."
    echo
    echo "Arquivo encontrado:"
    echo "/etc/kubernetes/admin.conf"
    echo
    echo "Para evitar uma inicialização duplicada, o script será encerrado."

    exit 1

fi

echo "Control Plane ainda não inicializado."
echo

# ============================================================
# Criar configuração kubeadm
# ============================================================

echo "[9/10] Criando configuração do kubeadm..."

mkdir -p /etc/kubernetes

cat > "$KUBEADM_CONFIG" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration

localAPIEndpoint:
  advertiseAddress: ${CONTROL_PLANE_IP}
  bindPort: 6443

nodeRegistration:
  name: ${CONTROL_PLANE_HOSTNAME}
  criSocket: ${CRI_SOCKET}

---

apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

kubernetesVersion: ${KUBERNETES_VERSION}

controlPlaneEndpoint: "${CONTROL_PLANE_IP}:6443"

networking:
  podSubnet: ${POD_NETWORK_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
  dnsDomain: cluster.local
EOF

chmod 600 "$KUBEADM_CONFIG"

echo
echo "Configuração criada:"
echo

cat "$KUBEADM_CONFIG"

echo

# ============================================================
# Validar configuração
# ============================================================

echo "Validando configuração do kubeadm..."

kubeadm config validate \
    --config "$KUBEADM_CONFIG"

echo
echo "Configuração: OK"
echo

# ============================================================
# Pré-baixar imagens
# ============================================================

echo "[10/10] Pré-baixando imagens do Kubernetes..."

kubeadm config images pull \
    --config "$KUBEADM_CONFIG"

echo
echo "Imagens: OK"
echo

# ============================================================
# Resumo
# ============================================================

echo "============================================================"
echo " CONFIGURAÇÃO DO CONTROL PLANE"
echo "============================================================"
echo
echo "Hostname        : $CONTROL_PLANE_HOSTNAME"
echo "IP              : $CONTROL_PLANE_IP"
echo "Kubernetes      : $KUBERNETES_VERSION"
echo "Pod Network     : $POD_NETWORK_CIDR"
echo "Service Network : $SERVICE_CIDR"
echo "CNI             : Flannel"
echo "CRI             : containerd"
echo

echo "O comando que será executado:"
echo
echo "kubeadm init --config $KUBEADM_CONFIG"
echo

echo "============================================================"
echo " ATENÇÃO"
echo "============================================================"
echo
echo "O próximo passo irá inicializar o Control Plane."
echo
echo "Isso criará:"
echo
echo "  - Kubernetes API Server"
echo "  - Controller Manager"
echo "  - Scheduler"
echo "  - etcd"
echo "  - certificados Kubernetes"
echo "  - kubeconfig"
echo
echo "============================================================"
echo

read -r -p "Continuar com kubeadm init? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then

    echo
    echo "Operação cancelada pelo usuário."
    echo
    exit 0

fi

# ============================================================
# Inicializar Control Plane
# ============================================================

echo
echo "============================================================"
echo " Inicializando Control Plane"
echo "============================================================"
echo

kubeadm init \
    --config "$KUBEADM_CONFIG"

echo

# ============================================================
# Configurar kubeconfig
# ============================================================

echo "Configurando kubeconfig..."

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then

    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

    mkdir -p "$USER_HOME/.kube"

    cp -f \
        /etc/kubernetes/admin.conf \
        "$USER_HOME/.kube/config"

    chown \
        "$SUDO_USER:$SUDO_USER" \
        "$USER_HOME/.kube/config"

    chmod 600 "$USER_HOME/.kube/config"

    echo "kubeconfig configurado para: $SUDO_USER"

else

    export KUBECONFIG=/etc/kubernetes/admin.conf

    echo "KUBECONFIG configurado para root."

fi

echo

# ============================================================
# Validação do cluster
# ============================================================

echo "============================================================"
echo " VALIDAÇÃO DO CONTROL PLANE"
echo "============================================================"
echo

echo "Cluster:"
kubectl cluster-info

echo

echo "Nodes:"
kubectl get nodes -o wide

echo

echo "Pods:"
kubectl get pods -A

echo

# ============================================================
# Final
# ============================================================

echo "============================================================"
echo " CONTROL PLANE INICIALIZADO COM SUCESSO"
echo "============================================================"
echo
echo "Hostname : $CONTROL_PLANE_HOSTNAME"
echo "IP       : $CONTROL_PLANE_IP"
echo
echo "Pod CIDR : $POD_NETWORK_CIDR"
echo
echo "CNI      : Flannel"
echo
echo "Próxima etapa:"
echo
echo "  1. Instalar Flannel"
echo "  2. Validar CoreDNS"
echo "  3. Gerar kubeadm join"
echo "  4. Adicionar os Workers"
echo