#!/bin/bash

set -euo pipefail

# ============================================================
# Preparação do Node - Homelab Kubernetes
# ============================================================
#
# Uso:
#   sudo ./01-prepare-node.sh
#
# Opcionalmente informe o hostname esperado:
#   sudo ./01-prepare-node.sh s0076-kubernetes-master-prd
#   sudo ./01-prepare-node.sh s0077-kubernetes-worker-prd
#
# ============================================================

echo
echo "============================================================"
echo " Preparação do Node - Homelab Kubernetes"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute este script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./prepare-node.sh"
    exit 1
fi

# ============================================================
# Informações do sistema
# ============================================================

CURRENT_HOSTNAME=$(hostname)

echo "Hostname : $CURRENT_HOSTNAME"
echo "Kernel   : $(uname -r)"
echo "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)"
echo

# ============================================================
# Validar hostname informado
# ============================================================

if [ -n "${1:-}" ]; then

    EXPECTED_HOSTNAME="$1"

    if [ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]; then
        echo "ERRO: hostname diferente do esperado."
        echo
        echo "Atual   : $CURRENT_HOSTNAME"
        echo "Esperado: $EXPECTED_HOSTNAME"
        echo
        echo "Altere o hostname antes de continuar:"
        echo "  hostnamectl set-hostname $EXPECTED_HOSTNAME"
        exit 1
    fi

    echo "Hostname validado: OK"
    echo
fi

# ============================================================
# Atualizar sistema
# ============================================================

echo "[1/8] Atualizando sistema..."

apt update

echo
echo "Índices de pacotes atualizados."
echo

# ============================================================
# Instalar dependências
# ============================================================

echo "[2/8] Instalando pacotes básicos..."

apt install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    socat \
    conntrack \
    ipset \
    iptables \
    ebtables \
    ethtool \
    chrony \
    jq

echo
echo "Pacotes instalados."
echo

# ============================================================
# Desabilitar Swap
# ============================================================

echo "[3/8] Desabilitando Swap..."

swapoff -a

# Remover entradas de swap do fstab sem alterar outras linhas
sed -i '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

echo
echo "Swap atual:"
free -h | grep -i swap

echo

# ============================================================
# Configurar módulos do Kernel
# ============================================================

echo "[4/8] Configurando módulos do Kernel..."

cat > /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo
echo "Módulos carregados:"
lsmod | grep -E 'overlay|br_netfilter' || true

echo

# ============================================================
# Configurar parâmetros do Kernel
# ============================================================

echo "[5/8] Configurando parâmetros do Kernel..."

cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

echo
echo "Parâmetros configurados:"
echo

sysctl \
    net.bridge.bridge-nf-call-iptables \
    net.bridge.bridge-nf-call-ip6tables \
    net.ipv4.ip_forward

echo

# ============================================================
# Configurar Chrony
# ============================================================

echo "[6/8] Configurando sincronização de horário..."

systemctl enable --now chrony

echo
echo "Status do Chrony:"
systemctl is-active chrony

echo
echo "Sincronização:"
chronyc tracking | grep -E \
    'Reference ID|Stratum|System time|Leap status' || true

echo

# ============================================================
# Validar /etc/hosts
# ============================================================

echo "[7/8] Validando resolução dos nós Kubernetes..."

HOSTS=(
    "192.168.250.76 s0076-kubernetes-master-prd"
    "192.168.250.77 s0077-kubernetes-worker-prd"
)

for HOST_ENTRY in "${HOSTS[@]}"; do

    IP=$(echo "$HOST_ENTRY" | awk '{print $1}')
    NAME=$(echo "$HOST_ENTRY" | awk '{print $2}')

    if getent hosts "$NAME" | awk -v ip="$IP" '$1 == ip {found=1} END {exit !found}'; then
        echo "OK: $NAME -> $IP"
    else
        echo "ERRO: resolução incorreta: $NAME -> $IP"
        exit 1
    fi

done

echo

# ============================================================
# Validar conectividade
# ============================================================

echo "[8/8] Testando conectividade..."

for IP in \
    192.168.250.76 \
    192.168.250.77
do

    if ping -c 2 -W 1 "$IP" >/dev/null 2>&1; then
        echo "OK: $IP"
    else
        echo "ERRO: $IP não respondeu"
        exit 1
    fi

done

echo


# ============================================================
# Validação final
# ============================================================

echo "============================================================"
echo " Validação Final"
echo "============================================================"
echo

ERRORS=0

echo "Hostname:"
hostnamectl --static

echo
echo "IP:"
ip -br addr

echo
echo "Swap:"
if swapon --show | grep -q .; then
    echo "ERRO: Swap ainda está habilitado."
    ERRORS=$((ERRORS + 1))
else
    echo "OK: Swap desabilitado."
fi

echo
echo "Kernel Modules:"
lsmod | grep -E 'overlay|br_netfilter' || true

if ! lsmod | grep -q '^overlay'; then
    echo "ERRO: overlay não está carregado."
    ERRORS=$((ERRORS + 1))
fi

if ! lsmod | grep -q '^br_netfilter'; then
    echo "ERRO: br_netfilter não está carregado."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "IP Forward:"
if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
    echo "OK: IP Forward habilitado."
else
    echo "ERRO: IP Forward desabilitado."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "Chrony:"
if systemctl is-active --quiet chrony; then
    echo "OK: Chrony ativo."
else
    echo "ERRO: Chrony não está ativo."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "============================================================"

if [[ "$ERRORS" -gt 0 ]]; then
    echo " FALHA: $ERRORS validação(ões) não passaram."
    exit 1
fi

echo " NODE PREPARADO COM SUCESSO"
echo "============================================================"
echo
echo "Hostname : $CURRENT_HOSTNAME"
echo
echo "Próxima etapa:"
echo "  Instalação e configuração do containerd"
